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
  wroteHeader : Bool
  closed : Bool
  buf : FixedArray[Byte] // [10]byte
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
    wroteHeader: false,
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
