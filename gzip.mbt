/// This package is based on the Go implementation found here:
/// https://cs.opensource.google/go/go/+/refs/tags/go1.23.0:src/compress/gzip/gzip.go
/// which has the copyright notice:
/// Copyright 2010 The Go Authors. All rights reserved.
/// Use of this source code is governed by a BSD-style
/// license that can be found in the LICENSE file.

pub type CompressionLevel Int derive(Show, Compare, Eq)

pub let huffman_only : CompressionLevel = -2

pub let default_compression : CompressionLevel = -1

pub let no_compression : CompressionLevel = 0

pub let best_speed : CompressionLevel = 1

pub let best_compression : CompressionLevel = 9

pub trait IOWriter {
  write(Self, Bytes) -> Result[Unit, Error]
}

/// Writes to a Writer are compressed and written to w.
pub struct Writer {
  header : Header // written at first call to Write, Flush, or Close
  w : IOWriter
  level : CompressionLevel
  mut wrote_header : Bool
  closed : Bool
  mut buf : FixedArray[Byte] // [10]byte
  compressor : IOWriter
  digest : UInt // CRC-32, IEEE polynomial (section 8)
  size : UInt // Uncompressed size (section 2.3.1)
  err : Error?
}

pub type! GzipError String derive(Show)

/// Writer::new returns a new [Writer] using the optional compression level
/// (or `default_compression`).
/// Writes to the returned writer are compressed and written to w.
///
/// It is the caller's responsibility to call Close on the [Writer] when done.
/// Writes may be buffered and not flushed until Close.
///
/// Callers that wish to set the fields in Writer.Header must do so before
/// the first call to Write, Flush, or Close.
pub fn Writer::new(
  w : IOWriter,
  ~level : CompressionLevel = default_compression
) -> Writer!GzipError {
  if level < huffman_only || level > best_compression {
    raise GzipError("gzip: invalid compression level: \{level}")
  }
  let header = Header::new()
  let buf = FixedArray::make(10, b'\x00')
  {
    header,
    w,
    level,
    wrote_header: false,
    closed: false,
    buf,
    compressor: w,
    digest: 0U, // CRC-32, IEEE polynomial (section 8)
    size: 0U, // Uncompressed size (section 2.3.1)
    err: None,
  }
}

// write_bytes writes a length-prefixed byte slice to self.w.
fn write_bytes(self : Writer, b : Bytes) -> Unit!GzipError {
  if b.length() > 0xffff {
    raise GzipError("gzip.Write: Extra data is too large")
  }
  le_put_uint16(self.buf, 0, b.length().reinterpret_as_uint())
  let le_len = Bytes::from_array([self.buf[0], self.buf[1]])
  match self.w.write(le_len) {
    Ok(_) => ()
    e => raise GzipError("write_bytes error: \{e}")
  }
  match self.w.write(b) {
    Ok(_) => ()
    e => raise GzipError("write_bytes error: \{e}")
  }
}

fn le_put_uint16(b : FixedArray[Byte], offset : Int, value : UInt) -> Unit {
  b[offset] = (value & 0xff).to_byte()
  b[offset + 1] = (value.lsr(8) & 0xff).to_byte()
}

/// write_string converts a UTF-16 String to UTF-8 and writes the UTF-8 string in GZIP's format to self.w.
/// GZIP (RFC 1952) specifies that strings are NUL-terminated ISO 8859-1 (Latin-1).
fn write_string(self : Writer, s : String) -> Unit!GzipError {
  // GZIP stores Latin-1 strings; error if non-Latin-1; convert if non-ASCII.
  for v in s {
    if v == Char::from_int(0) || v > Char::from_int(0xff) {
      raise GzipError("@gzip.write_string: non-Latin-1 header string")
    }
  }
  let b = @base64.str2bytes(s)
  match self.w.write(b) {
    Ok(_) => ()
    e => raise GzipError("write_bytes error: \{e}")
  }
  // GZIP strings are NUL-terminated.
  let b = Bytes::make(1, b'\x00')
  match self.w.write(b) {
    Ok(_) => ()
    e => raise GzipError("write_bytes error: \{e}")
  }
}

// write writes a compressed form of p to the underlying [io.Writer]. The
// compressed bytes are not necessarily flushed until the [Writer] is closed.
pub fn write(self: Writer, p : Bytes) -> Int!Error {
	match self.err {
    Some(e) => raise e
    None => ()
	}
  let mut n = 0
	// Write the GZIP header lazily.
	if not(self.wrote_header) {
		self.wrote_header = true
    self.buf = FixedArray::make(10, b'\x00')
    self.buf[0] = gzip_id1
    self.buf[1] = gzip_id2
    self.buf[2] = gzip_deflate
		match self.header.extra {
      Some(_) => self.buf[3] = b'\x04'
      None => ()
		}
		if self.header.name != "" {
			self.buf[3] = self.buf[3] | b'\x08'
		}
		if self.header.comment != "" {
			self.buf[3] = self.buf[3] | b'\x10'
		}
		match self.mod_time {
      Some(t) => {
        let t = t.seconds.to_uint()
			  // Section 2.3.1, the zero value for MTIME means that the
			  // modified time is not set.
			  le_put_uint32(self.buf, 4, t)
      }
      None => ()
		}
		if self.level == best_compression {
			self.buf[8] = 2
		} else if self.level == best_speed {
			self.buf[8] = 4
		}
		self.buf[9] = self.os
		_, self.err = self.w.Write(self.buf)
		if self.err != nil {
			return 0, self.err
		}
		if self.Extra != nil {
			self.err = self.writeBytes(self.Extra)
			if self.err != nil {
				return 0, self.err
			}
		}
		if self.Name != "" {
			self.err = self.writeString(self.Name)
			if self.err != nil {
				return 0, self.err
			}
		}
		if self.Comment != "" {
			self.err = self.writeString(self.Comment)
			if self.err != nil {
				return 0, self.err
			}
		}
		if self.compressor == nil {
			self.compressor, _ = flate.NewWriter(self.w, self.level)
		}
	}
	self.size += uint32(len(p))
	self.digest = crc32.Update(self.digest, crc32.IEEETable, p)
	n, self.err = self.compressor.Write(p)
	return n, self.err
}

/// flush flushes any pending compressed data to the underlying writer.
///
/// It is useful mainly in compressed network protocols, to ensure that
/// a remote reader has enough data to reconstruct a packet. Flush does
/// not return until the data has been written. If the underlying
/// writer returns an error, Flush returns that error.
///
/// In the terminology of the zlib library, Flush is equivalent to Z_SYNC_FLUSH.
pub fn flush(self: Writer) -> Unit!GzipError {
	if self.err != nil {
		return self.err
	}
	if self.closed {
		return nil
	}
	if !self.wrote_header {
		self.Write(nil)
		if self.err != nil {
			return self.err
		}
	}
	self.err = self.compressor.Flush()
	return self.err
}

/// close closes the [Writer] by flushing any unwritten data to the underlying
/// [io.Writer] and writing the GZIP footer.
/// It does not close the underlying [io.Writer].
pub fn close(self: Writer, ) -> Unit!GzipError {
	if self.err != nil {
		return self.err
	}
	if self.closed {
		return nil
	}
	self.closed = true
	if !self.wrote_header {
		self.Write(nil)
		if self.err != nil {
			return self.err
		}
	}
	self.err = self.compressor.Close()
	if self.err != nil {
		return self.err
	}
	le.PutUint32(self.buf[:4], self.digest)
	le.PutUint32(self.buf[4:8], self.size)
	_, self.err = self.w.Write(self.buf[:8])
	return self.err
}
