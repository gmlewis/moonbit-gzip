// -*- compile-command: "moon test --target js > got.txt"; -*-

// This package is based on the Go implementation found here:
// https://cs.opensource.google/go/go/+/refs/tags/go1.23.0:src/compress/gzip/gzip.go
// which has the copyright notice:
// Copyright 2010 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

///|
pub(all) type CompressionLevel Int derive(Show, Compare, Eq)

// pub let huffman_only : CompressionLevel = -2

// pub let default_compression : CompressionLevel = -1

// pub let no_compression : CompressionLevel = 0

///|
pub let best_speed : CompressionLevel = 1

// pub let best_compression : CompressionLevel = 9

///|
/// Writes to a Writer are compressed and written to w.
pub(all) struct Writer {
  header : Header // written at first call to Write, Flush, or Close
  w : &@io.Writer
  level : CompressionLevel
  mut wrote_header : Bool
  mut closed : Bool
  mut buf : Array[Byte] // [10]byte
  mut compressor : &@io.WriteCloser
  mut digest : UInt // CRC-32, IEEE polynomial (section 8)
  mut size : UInt // Uncompressed size (section 2.3.1)
  mut err : IOError?
}

///|
fn gzip_error(s : String) -> IOError {
  IOError(s)
}

///|
/// Writer::new returns a new [IOWriter] using the optional compression level
/// (or `default_compression`).
/// Writes to the returned writer are compressed and written to w.
///
/// It is the caller's responsibility to call Close on the [Writer] when done.
/// Writes may be buffered and not flushed until Close.
///
/// Callers that wish to set the fields in Writer.Header must do so before
/// the first call to Write, Flush, or Close.
pub fn Writer::new(w : &@io.Writer) -> Writer {
  let header = Header::new()
  let buf = Array::make(10, b'\x00')
  {
    header,
    w,
    level: best_speed,
    wrote_header: false,
    closed: false,
    buf,
    compressor: @flate.Writer::new(w),
    digest: 0U, // CRC-32, IEEE polynomial (section 8)
    size: 0U, // Uncompressed size (section 2.3.1)
    err: None,
  }
}

///|
// write_bytes writes a length-prefixed byte slice to self.w.
fn write_bytes(self : Writer, b : Slice[Byte]) -> IOError? {
  if b.length() > 0xffff {
    return Some(gzip_error("gzip.Write: Extra data is too large"))
  }
  le_put_uint16(self.buf, 0, b.length().reinterpret_as_uint())
  let le_len = [self.buf[0], self.buf[1]]
  let (_, err) = self.w.write(Slice::new(le_len)[:])
  guard err is None else { return err }
  let (_, err) = self.w.write(b)
  err
}

///|
fn le_put_uint16(b : Array[Byte], offset : Int, value : UInt) -> Unit {
  b[offset] = (value & 0xff).to_byte()
  b[offset + 1] = ((value >> 8) & 0xff).to_byte()
}

///|
fn le_put_uint32(b : Array[Byte], offset : Int, value : UInt) -> Unit {
  b[offset] = (value & 0xff).to_byte()
  b[offset + 1] = ((value >> 8) & 0xff).to_byte()
  b[offset + 2] = ((value >> 16) & 0xff).to_byte()
  b[offset + 3] = ((value >> 24) & 0xff).to_byte()
}

// fn le_put_uint64(b : Array[Byte], offset : Int, value : UInt64) -> Unit {
//   le_put_uint32(b, offset, (value & 0xffffffff).to_uint())
//   le_put_uint32(b, offset + 4, ((value >> 32) & 0xffffffff).to_uint())
// }

///|
/// write_string converts a UTF-16 String to UTF-8 and writes the UTF-8 string in GZIP's format to self.w.
/// GZIP (RFC 1952) specifies that strings are NUL-terminated ISO 8859-1 (Latin-1).
fn write_string(self : Writer, s : String) -> IOError? {
  let ch = s.to_array()
  // GZIP stores Latin-1 strings; error if non-Latin-1; convert if non-ASCII.
  let mut needconv = false
  for c in ch {
    let v = c.to_int()
    if v == 0 || v >= 0xff {
      return Some(gzip_error("@gzip.write_string: non-Latin-1 header string"))
    }
    if v > 0x7f {
      needconv = true
    }
  }
  if needconv {
    let b = Slice::new(Array::make(s.length(), b'\x00'))
    for i in 0..<s.length() {
      let v = s.unsafe_charcode_at(i)
      b[i] = (v.reinterpret_as_uint() & 0xff).to_byte()
    }
    let (_, err) = self.w.write(b)
    guard err is None else { return err }
  } else {
    let b = @base64.str2bytes(s).to_array()
    let (_, err) = self.w.write(Slice::new(b))
    guard err is None else { return err }
  }

  // GZIP strings are NUL-terminated.
  let (_, err) = self.w.write(Slice::new([b'\x00']))
  guard err is None else { return err }
  None
}

///|
// write writes a compressed form of p to the underlying [io.Writer]. The
// compressed bytes are not necessarily flushed until the [Writer] is closed.
pub impl @io.Writer for Writer with write(self, p) {
  match self.err {
    Some(_) => return (0, self.err)
    _ => ()
  }
  // Write the GZIP header lazily.
  if not(self.wrote_header) {
    self.wrote_header = true
    self.buf = Array::make(10, b'\x00')
    self.buf[0] = gzip_id1
    self.buf[1] = gzip_id2
    self.buf[2] = gzip_deflate
    match self.header.extra {
      [] => ()
      _ => self.buf[3] = b'\x04'
    }
    if self.header.name != "" {
      self.buf[3] = self.buf[3] | b'\x08'
    }
    if self.header.comment != "" {
      self.buf[3] = self.buf[3] | b'\x10'
    }
    match self.header.mod_time {
      Some(t) => {
        let t = t.to_unix_second().reinterpret_as_uint64().to_uint()
        // Section 2.3.1, the zero value for MTIME means that the
        // modified time is not set.
        le_put_uint32(self.buf, 4, t)
      }
      None => ()
    }
    // This version only supports 'best_speed'.
    // if self.level == best_compression {
    //   self.buf[8] = b'\x02'
    // } else if self.level == best_speed {
    self.buf[8] = b'\x04'
    // }
    self.buf[9] = self.header.os
    let b = Slice::new(self.buf)
    let (_, err) = self.w.write(b)
    guard err is None else {
      self.err = err
      return (0, err)
    }
    match self.header.extra {
      [] => ()
      b => {
        let err = self.write_bytes(Slice::new(b))
        guard err is None else {
          self.err = err
          return (0, err)
        }
      }
    }
    if self.header.name != "" {
      let err = self.write_string(self.header.name)
      guard err is None else {
        self.err = err
        return (0, err)
      }
    }
    if self.header.comment != "" {
      let err = self.write_string(self.header.comment)
      guard err is None else {
        self.err = err
        return (0, err)
      }
    }
    // if z.compressor == nil {
    // 	log.Printf("GML: gzip.go: Write: header: W")
    // 	z.compressor, _ = flate.NewWriter(z.w, z.level)
    // }
  }
  self.size += p.length().reinterpret_as_uint()
  let sum = @crc32.Digest::new()
  for b in p {
    sum.write(b)
  }
  self.digest = sum.digest()
  let (n, err) = self.compressor.write(p)
  (n, err)
}

///|
/// flush flushes any pending compressed data to the underlying writer.
///
/// It is useful mainly in compressed network protocols, to ensure that
/// a remote reader has enough data to reconstruct a packet. Flush does
/// not return until the data has been written. If the underlying
/// writer returns an error, Flush returns that error.
///
/// In the terminology of the zlib library, Flush is equivalent to Z_SYNC_FLUSH.
pub fn flush(self : Writer) -> IOError? {
  guard self.err is None else { return self.err }
  if self.closed {
    return None
  }
  if not(self.wrote_header) {
    let (_, err) = self.write(Slice::new([b'\x00']))
    guard err is None else { return err }
  }
  // The simplified flate compressor has no flush method.
  // self.err = self.compressor.flush()
  None
}

///|
/// close closes the [Writer] by flushing any unwritten data to the underlying
/// [io.Writer] and writing the GZIP footer.
/// It does not close the underlying [io.Writer].
pub impl @io.Closer for Writer with close(self) {
  guard self.err is None else { return self.err }
  if self.closed {
    return None
  }
  self.closed = true
  if not(self.wrote_header) {
    let (_, err) = self.write(Slice::new([]))
    guard err is None else { return err }
  }
  self.err = self.compressor.close()
  le_put_uint32(self.buf, 0, self.digest)
  le_put_uint32(self.buf, 4, self.size)
  let footer = Slice::new(self.buf)[:8]
  let (_, err) = self.w.write(footer)
  err
}
