// -*- compile-command: "moon test --target js > got.txt"; -*-

pub let gml_debug : Ref[Bool] = { val: false }

pub fn gmldbg(s : String) -> Unit {
  if gml_debug.val {
    println(s)
  }
}

/// This package is based on the Go implementation found here:
/// https://cs.opensource.google/go/go/+/refs/tags/go1.23.0:src/compress/gzip/gzip.go
/// which has the copyright notice:
/// Copyright 2010 The Go Authors. All rights reserved.
/// Use of this source code is governed by a BSD-style
/// license that can be found in the LICENSE file.

pub type CompressionLevel Int derive(Show, Compare, Eq)

// pub let huffman_only : CompressionLevel = -2

// pub let default_compression : CompressionLevel = -1

// pub let no_compression : CompressionLevel = 0

pub let best_speed : CompressionLevel = 1

// pub let best_compression : CompressionLevel = 9

/// Writes to a Writer are compressed and written to w.
pub struct Writer {
  header : Header // written at first call to Write, Flush, or Close
  w : @flate.IOWriter
  level : CompressionLevel
  mut wrote_header : Bool
  mut closed : Bool
  mut buf : Array[Byte] // [10]byte
  mut compressor : @flate.IOWriteCloser
  mut digest : UInt // CRC-32, IEEE polynomial (section 8)
  mut size : UInt // Uncompressed size (section 2.3.1)
  mut err : Error?
}

pub type! GzipError String derive(Show)

/// Writer::new returns a new [IOWriter] using the optional compression level
/// (or `default_compression`).
/// Writes to the returned writer are compressed and written to w.
///
/// It is the caller's responsibility to call Close on the [Writer] when done.
/// Writes may be buffered and not flushed until Close.
///
/// Callers that wish to set the fields in Writer.Header must do so before
/// the first call to Write, Flush, or Close.
pub fn Writer::new(w : @flate.IOWriter) -> Writer {
  gmldbg(
    "GML: gzip.go: NewWriterLevel(w io.Writer, level int) (*Writer, error) {",
  )
  gmldbg("GML: gzip.go: (z *Writer) init(w io.Writer, level int) {")
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

// write_bytes writes a length-prefixed byte slice to self.w.
fn write_bytes(self : Writer, b : ArrayView[Byte]) -> Unit!Error {
  if b.length() > 0xffff {
    raise GzipError("gzip.Write: Extra data is too large")
  }
  le_put_uint16(self.buf, 0, b.length().reinterpret_as_uint())
  let le_len = [self.buf[0], self.buf[1]]
  let _ = self.w.write!(le_len[:])
  let _ = self.w.write!(b)

}

fn le_put_uint16(b : Array[Byte], offset : Int, value : UInt) -> Unit {
  b[offset] = (value & 0xff).to_byte()
  b[offset + 1] = ((value >> 8) & 0xff).to_byte()
}

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

/// write_string converts a UTF-16 String to UTF-8 and writes the UTF-8 string in GZIP's format to self.w.
/// GZIP (RFC 1952) specifies that strings are NUL-terminated ISO 8859-1 (Latin-1).
fn write_string(self : Writer, s : String) -> Unit!Error {
  // GZIP stores Latin-1 strings; error if non-Latin-1; convert if non-ASCII.
  for v in s {
    if v == Char::from_int(0) || v > Char::from_int(0xff) {
      raise GzipError("@gzip.write_string: non-Latin-1 header string")
    }
  }
  let b = @base64.str2bytes(s).to_array()[:]
  let _ = self.w.write!(b)
  // GZIP strings are NUL-terminated.
  let _ = self.w.write!([b'\x00'][:])

}

fn dump_av(buf : ArrayView[Byte]) -> String {
  buf.iter().map(fn(b) { b.to_int() }).to_string().replace_all(old=",", new="")
}

// write writes a compressed form of p to the underlying [io.Writer]. The
// compressed bytes are not necessarily flushed until the [Writer] is closed.
pub fn write(self : Writer, p : ArrayView[Byte]) -> Int!Error {
  gmldbg("GML: gzip.go: (z *Writer) Write(p=\{dump_av(p)}) (int, error) {")
  match self.err {
    Some(e) => raise e
    None => ()
  }
  // Write the GZIP header lazily.
  if not(self.wrote_header) {
    self.wrote_header = true
    self.buf = Array::make(10, b'\x00')
    self.buf[0] = gzip_id1
    self.buf[1] = gzip_id2
    self.buf[2] = gzip_deflate
    gmldbg("GML: gzip.go: Write: header: A")
    match self.header.extra {
      [] => ()
      _ => {
        self.buf[3] = b'\x04'
        gmldbg("GML: gzip.go: Write: header: B")
      }
    }
    if self.header.name != "" {
      self.buf[3] = self.buf[3] | b'\x08'
      gmldbg("GML: gzip.go: Write: header: C")
    }
    if self.header.comment != "" {
      self.buf[3] = self.buf[3] | b'\x10'
      gmldbg("GML: gzip.go: Write: header: D")
    }
    match self.header.mod_time {
      Some(t) => {
        let t = t.to_unix_second().reinterpret_as_uint64().to_uint()
        // Section 2.3.1, the zero value for MTIME means that the
        // modified time is not set.
        le_put_uint32(self.buf, 4, t)
        gmldbg("GML: gzip.go: Write: header: E")
      }
      None => ()
    }
    // This version only supports 'best_speed'.
    // if self.level == best_compression {
    //   self.buf[8] = b'\x02'
    // } else if self.level == best_speed {
    self.buf[8] = b'\x04'
    gmldbg("GML: gzip.go: Write: header: G")
    // }
    self.buf[9] = self.header.os
    gmldbg("GML: gzip.go: Write: header: H")
    let b = self.buf[:]
    let _ = try {
      self.w.write!(b)
    } catch {
      e => {
        self.err = Some(e)
        gmldbg("GML: gzip.go: Write: header: I")
        raise e
      }
    }
    gmldbg("GML: gzip.go: Write: header: J")
    match self.header.extra {
      [] => ()
      b => {
        gmldbg("GML: gzip.go: Write: header: K")
        try {
          self.write_bytes!(b[:])
        } catch {
          e => {
            self.err = Some(e)
            gmldbg("GML: gzip.go: Write: header: L")
            raise e
          }
        }
        gmldbg("GML: gzip.go: Write: header: M")
      }
    }
    gmldbg("GML: gzip.go: Write: header: N")
    if self.header.name != "" {
      gmldbg("GML: gzip.go: Write: header: O")
      try {
        self.write_string!(self.header.name)
      } catch {
        e => {
          self.err = Some(e)
          gmldbg("GML: gzip.go: Write: header: P")
          raise e
        }
      }
      gmldbg("GML: gzip.go: Write: header: Q")
    }
    gmldbg("GML: gzip.go: Write: header: R")
    if self.header.comment != "" {
      gmldbg("GML: gzip.go: Write: header: S")
      try {
        self.write_string!(self.header.comment)
      } catch {
        e => {
          self.err = Some(e)
          gmldbg("GML: gzip.go: Write: header: T")
          raise e
        }
      }
      gmldbg("GML: gzip.go: Write: header: U")
    }
    gmldbg("GML: gzip.go: Write: header: V")
    // if z.compressor == nil {
    // 	log.Printf("GML: gzip.go: Write: header: W")
    // 	z.compressor, _ = flate.NewWriter(z.w, z.level)
    // }
    gmldbg("GML: gzip.go: Write: header: X")
  }
  gmldbg("GML: gzip.go: Write: header: Y")
  self.size += p.length().reinterpret_as_uint()
  gmldbg("GML: gzip.go: Write: header: Y1: z.size=\{self.size}")
  let sum = @crc32.Digest::new()
  for b in p {
    sum.write(b)
  }
  self.digest = sum.digest()
  gmldbg("GML: gzip.go: Write: header: Y2: z.digest=\{self.digest}")
  try {
    let n = self.compressor.write!(p)
    gmldbg("GML: gzip.go: Write: header: Z: n=\{n}")
    n
  } catch {
    e => {
      self.err = Some(e)
      gmldbg("GML: gzip.go: Write: header: Z: err=???")
      raise e
    }
  }
}

/// flush flushes any pending compressed data to the underlying writer.
///
/// It is useful mainly in compressed network protocols, to ensure that
/// a remote reader has enough data to reconstruct a packet. Flush does
/// not return until the data has been written. If the underlying
/// writer returns an error, Flush returns that error.
///
/// In the terminology of the zlib library, Flush is equivalent to Z_SYNC_FLUSH.
pub fn flush(self : Writer) -> Unit!Error {
  match self.err {
    Some(e) => raise e
    None => ()
  }
  if self.closed {
    return
  }
  if not(self.wrote_header) {
    let _ = self.write!([b'\x00'][:])
    match self.err {
      Some(e) => raise e
      None => ()
    }
  }
  // self.err = self.compressor.flush()
}

/// close closes the [Writer] by flushing any unwritten data to the underlying
/// [io.Writer] and writing the GZIP footer.
/// It does not close the underlying [io.Writer].
pub fn close(self : Writer) -> Unit!Error {
  gmldbg("GML: gzip.go: (z *Writer) Close() error {")
  match self.err {
    Some(e) => raise e
    None => ()
  }
  if self.closed {
    return
  }
  self.closed = true
  if not(self.wrote_header) {
    let _ = self.write!([][:])
    match self.err {
      Some(e) => raise e
      None => ()
    }
  }
  try {
    self.compressor.close!()
  } catch {
    e => self.err = Some(e)
  }
  le_put_uint32(self.buf, 0, self.digest)
  le_put_uint32(self.buf, 4, self.size)
  let footer = [
      self.buf[0],
      self.buf[1],
      self.buf[2],
      self.buf[3],
      self.buf[4],
      self.buf[5],
      self.buf[6],
      self.buf[7],
    ][:]
  let _ = self.w.write!(footer)

}

let io_read_buf_size = 1024

pub fn read_all(self : Reader) -> Bytes!Error {
  let buf = @buffer.new()
  let b = Array::make(io_read_buf_size, b'\x00')
  for {
    let n = try {
      self.read!(b[:])
    } catch {
      @flate.IOEOF => 0
      e => raise e
    }
    if n == 0 {
      break
    }
    for i = 0; i < n; i = i + 1 {
      buf.write_byte(b[i])
    }
  }
  buf.to_bytes()
}
