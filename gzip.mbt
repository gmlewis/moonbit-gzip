// -*- compile-command: "moon test --target js > got.txt"; -*-

pub let gml_debug : Ref[Bool] = { val: false }

pub fn gmldbg(s : String) -> Unit {
  if gml_debug.val {
    println(s)
  }
}

// This package is based on the Go implementation found here:
// https://cs.opensource.google/go/go/+/refs/tags/go1.23.0:src/compress/gzip/gzip.go
// which has the copyright notice:
// Copyright 2010 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

pub type CompressionLevel Int derive(Show, Compare, Eq)

// pub let huffman_only : CompressionLevel = -2

// pub let default_compression : CompressionLevel = -1

// pub let no_compression : CompressionLevel = 0

pub let best_speed : CompressionLevel = 1

// pub let best_compression : CompressionLevel = 9

/// Writes to a Writer are compressed and written to w.
pub struct Writer {
  header : Header // written at first call to Write, Flush, or Close
  w : @io.Writer
  level : CompressionLevel
  mut wrote_header : Bool
  mut closed : Bool
  mut buf : Array[Byte] // [10]byte
  mut compressor : @io.WriteCloser
  mut digest : UInt // CRC-32, IEEE polynomial (section 8)
  mut size : UInt // Uncompressed size (section 2.3.1)
  mut err : IOError?
}

fn gzip_error(s : String) -> IOError {
  IOError(s)
}

/// Writer::new returns a new [IOWriter] using the optional compression level
/// (or `default_compression`).
/// Writes to the returned writer are compressed and written to w.
///
/// It is the caller's responsibility to call Close on the [Writer] when done.
/// Writes may be buffered and not flushed until Close.
///
/// Callers that wish to set the fields in Writer.Header must do so before
/// the first call to Write, Flush, or Close.
pub fn Writer::new(w : @io.Writer) -> Writer {
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
fn write_bytes(self : Writer, b : Slice[Byte]) -> IOError? {
  if b.length() > 0xffff {
    return Some(gzip_error("gzip.Write: Extra data is too large"))
  }
  le_put_uint16(self.buf, 0, b.length().reinterpret_as_uint())
  let le_len = [self.buf[0], self.buf[1]]
  let (_, err) = self.w.write(Slice::new(le_len)[:])
  guard let None = err else { _ => return err }
  let (_, err) = self.w.write(b)
  err
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
fn write_string(self : Writer, s : String) -> IOError? {
  gmldbg("GML: gzip.go: (z *Writer) writeString(s string) (err error) {")
  let ch = s.to_array()
  // GZIP stores Latin-1 strings; error if non-Latin-1; convert if non-ASCII.
  let mut needconv = false
  for c in ch {
    let v = c.to_int()
    gmldbg("GML: gzip.go: writeString: A: v=\{v}")
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
      let v = s[i]
      gmldbg("GML: gzip.go: writeString: B: v=\{v.to_int()}")
      b[i] = (v.to_uint() & 0xff).to_byte()
    }
    let (_, err) = self.w.write(b)
    guard let None = err else { _ => return err }

  } else {
    let b = @base64.str2bytes(s).to_array()
    gmldbg("GML: gzip.go: writeString: C: s=\{dump_av(b[:])}")
    let (_, err) = self.w.write(Slice::new(b))
    guard let None = err else { _ => return err }

  }

  // GZIP strings are NUL-terminated.
  let (_, err) = self.w.write(Slice::new([b'\x00']))
  guard let None = err else { _ => return err }
  gmldbg("GML: gzip.go: writeString: D")
  None
}

pub fn dump_av(buf : ArrayView[Byte]) -> String {
  buf.iter().map(fn(b) { b.to_int() }).to_string().replace_all(old=",", new="")
}

pub fn dump_slice(buf : Slice[Byte]) -> String {
  buf.iter().map(fn(b) { b.to_int() }).to_string().replace_all(old=",", new="")
}

// write writes a compressed form of p to the underlying [io.Writer]. The
// compressed bytes are not necessarily flushed until the [Writer] is closed.
pub fn write(self : Writer, p : Slice[Byte]) -> (Int, IOError?) {
  gmldbg("GML: gzip.go: (z *Writer) Write(p=\{dump_slice(p)}) (int, error) {")
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
    let b = Slice::new(self.buf)
    let (_, err) = self.w.write(b)
    guard let None = err else {
      _ => {
        self.err = err
        gmldbg("GML: gzip.go: Write: header: I")
        return (0, err)
      }
    }
    gmldbg("GML: gzip.go: Write: header: J")
    match self.header.extra {
      [] => ()
      b => {
        gmldbg("GML: gzip.go: Write: header: K")
        guard let None = self.write_bytes(Slice::new(b)) else {
          e => {
            self.err = e
            gmldbg("GML: gzip.go: Write: header: L")
            return (0, e)
          }
        }
        gmldbg("GML: gzip.go: Write: header: M")
      }
    }
    gmldbg("GML: gzip.go: Write: header: N")
    if self.header.name != "" {
      gmldbg("GML: gzip.go: Write: header: O")
      guard let None = self.write_string(self.header.name) else {
        e => {
          self.err = e
          gmldbg("GML: gzip.go: Write: header: P: z.err=\{e}")
          return (0, e)
        }
      }
      gmldbg("GML: gzip.go: Write: header: Q")
    }
    gmldbg("GML: gzip.go: Write: header: R")
    if self.header.comment != "" {
      gmldbg("GML: gzip.go: Write: header: S")
      guard let None = self.write_string(self.header.comment) else {
        e => {
          self.err = e
          gmldbg("GML: gzip.go: Write: header: T")
          return (0, e)
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
  let (n, err) = self.compressor.write(p)
  gmldbg("GML: gzip.go: Write: header: Z: n=\{n}, err=\{err}")
  (n, err)
}

/// flush flushes any pending compressed data to the underlying writer.
///
/// It is useful mainly in compressed network protocols, to ensure that
/// a remote reader has enough data to reconstruct a packet. Flush does
/// not return until the data has been written. If the underlying
/// writer returns an error, Flush returns that error.
///
/// In the terminology of the zlib library, Flush is equivalent to Z_SYNC_FLUSH.
pub fn flush(self : Writer) -> IOError? {
  guard let None = self.err else { _ => return self.err }
  if self.closed {
    return None
  }
  if not(self.wrote_header) {
    guard let (_, None) = self.write(Slice::new([b'\x00'])) else {
      (_, e) => return e
    }

  }
  // The simplified flate compressor has no flush method.
  // self.err = self.compressor.flush()
  None
}

/// close closes the [Writer] by flushing any unwritten data to the underlying
/// [io.Writer] and writing the GZIP footer.
/// It does not close the underlying [io.Writer].
pub fn close(self : Writer) -> IOError? {
  gmldbg("GML: gzip.go: (z *Writer) Close() error {")
  guard let None = self.err else { _ => return self.err }
  if self.closed {
    return None
  }
  self.closed = true
  if not(self.wrote_header) {
    guard let (_, None) = self.write(Slice::new([])) else { (_, e) => return e }

  }
  self.err = self.compressor.close()
  le_put_uint32(self.buf, 0, self.digest)
  le_put_uint32(self.buf, 4, self.size)
  let footer = Slice::new(self.buf)[:8]
  let (_, err) = self.w.write(footer)
  err
}
