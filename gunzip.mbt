// -*- compile-command: "moon test --target js > got.txt"; -*-

// This package is based on the Go implementation found here:
// https://cs.opensource.google/go/go/+/refs/tags/go1.23.0:src/compress/gzip/gunzip.go
// which has the copyright notice:
// Copyright 2009 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

let gzip_id1 = b'\x1f'

let gzip_id2 = b'\x8b'

let gzip_deflate : Byte = b'\x08'

// let flag_text : Byte = b'\x01'

let flag_hdr_crc : Byte = b'\x02'

let flag_extra : Byte = b'\x04'

let flag_name : Byte = b'\x08'

let flag_comment : Byte = b'\x10'

// ErrChecksum is returned when reading GZIP data that has an invalid checksum.
pub type! ErrChecksum  derive(Show, Eq)

// ErrHeader is returned when reading GZIP data that has an invalid header.
pub type! ErrHeader  derive(Show, Eq)

pub type! ErrUnexpectedEOF  derive(Show, Eq)

pub type! IOEOF  derive(Show, Eq)

// var le = binary.LittleEndian

// no_eof converts IOEOF to io.ErrUnexpectedEOF.
fn no_eof(err : Error) -> Error {
  gmldbg("GML: gunzip.go: noEOF(err error) error { // err=???")
  match err {
    IOEOF => ErrUnexpectedEOF
    e => e
  }
}

/// The gzip file stores a header giving metadata about the compressed file.
/// That header is exposed as the fields of the [Writer] and [Reader] structs.
///
/// Strings must be UTF-8 encoded and may only contain Unicode code points
/// U+0001 through U+00FF, due to limitations of the GZIP file format.
pub struct Header {
  mut comment : String // comment
  mut extra : Array[Byte] // "extra data"
  mut mod_time : @time.PlainDateTime? // modification time
  mut name : String // file name
  mut os : Byte // operating system type
}

pub fn Header::new() -> Header {
  { comment: "", extra: [], mod_time: None, name: "", os: b'\xff' }
}

// A Reader is an [IOReadCloser] that can be read to retrieve
// uncompressed data from a gzip-format compressed file.
//
// In general, a gzip file can be a concatenation of gzip files,
// each with its own header. Reads from the Reader
// return the concatenation of the uncompressed data of each.
// Only the first header is recorded in the Reader fields.
//
// Gzip files store a length and checksum of the uncompressed data.
// The Reader will return an [ErrChecksum] when [Reader.Read]
// reaches the end of the uncompressed data if it does not
// have the expected length or checksum. Clients should treat data
// returned by [Reader.Read] as tentative until they receive the [IOEOF]
// marking the end of the data.
pub struct Reader {
  mut header : Header // valid after NewReader or Reader.Reset
  priv mut r : @flate.IOReader
  priv mut decompressor : @flate.IOReadCloser
  priv mut digest : @crc32.Digest // CRC-32, IEEE polynomial (section 8)
  priv mut size : UInt // Uncompressed size (section 2.3.1)
  priv mut buf : Array[Byte] // [512]byte
  priv mut err : Error?
  priv mut multistream : Bool
}

// NewReader creates a new [IOReader] reading the given reader.
//
// It is the caller's responsibility to call Close on the [Reader] when done.
//
// The [Reader.Header] fields will be valid in the [Reader] returned.
pub fn Reader::new(r : @flate.IOReader) -> Reader {
  gmldbg("GML: gunzip.go: NewReader(r io.Reader) (*Reader, error) {")
  let z = {
    header: Header::new(),
    r,
    decompressor: @flate.Reader::new(r),
    digest: @crc32.Digest::new(),
    size: 0,
    buf: [],
    err: None,
    multistream: false,
  }
  try {
    let reader = z.reset!(r)
    gmldbg("GML: gunzip.go: NewReader: no err")
    reader
  } catch {
    _ =>
      // gmldbg("GML: gunzip.go: NewReader: err=???")
      z
  }
}

// Reset discards the [Reader] z's state and makes it equivalent to the
// result of its original state from [NewReader], but reading from r instead.
// This permits reusing a [Reader] rather than allocating a new one.
pub fn reset(self : Reader, r : @flate.IOReader) -> Reader!Error {
  gmldbg("GML: gunzip.go: (z *Reader) Reset(r io.Reader) error {")
  gmldbg("GML: gunzip.go: Reset: A")
  self.r = r
  self.digest = @crc32.Digest::new()
  self.size = 0
  self.buf = Array::make(512, b'\x00')
  self.err = None
  self.multistream = true
  self.header = try {
    let header = self.read_header!()
    gmldbg("GML: gunzip.go: Reset: C: z.err=<nil>")
    header
  } catch {
    e => {
      self.err = Some(e)
      gmldbg("GML: gunzip.go: Reset: C: z.err=\{self.err}")
      raise e
    }
  }
  self
}

// Multistream controls whether the reader supports multistream files.
//
// If enabled (the default), the [Reader] expects the input to be a sequence
// of individually gzipped data streams, each with its own header and
// trailer, ending at EOF. The effect is that the concatenation of a sequence
// of gzipped files is treated as equivalent to the gzip of the concatenation
// of the sequence. This is standard behavior for gzip readers.
//
// Calling Multistream(false) disables this behavior; disabling the behavior
// can be useful when reading file formats that distinguish individual gzip
// data streams or mix gzip data streams with other data streams.
// In this mode, when the [Reader] reaches the end of the data stream,
// [Reader.Read] returns [IOEOF]. The underlying reader must implement [io.ByteReader]
// in order to be left positioned just after the gzip stream.
// To start the next stream, call self.Reset(r) followed by self.Multistream(false).
// If there is no next stream, self.Reset(r) will return [IOEOF].
pub fn multistream(self : Reader, ok : Bool) -> Unit {
  gmldbg("GML: gunzip.go: (z *Reader) Multistream(ok=\{ok}) {")
  self.multistream = ok
}

// read_string reads a NUL-terminated string from self.r.
// It treats the bytes read as being encoded as ISO 8859-1 (Latin-1) and
// will output a string encoded using UTF-8.
// This method always updates self.digest with the data read.
fn read_string(self : Reader) -> String!Error {
  gmldbg("GML: gunzip.go: (z *Reader) readString() (string, error) {")
  let mut need_conv = false
  for i = 0; true; i = i + 1 {
    if i >= self.buf.length() {
      raise ErrHeader
    }
    self.buf[i] = self.r.read_byte!()
    gmldbg(
      "GML: readString: A: consumed 1 byte from reader: [\{self.buf[i].to_int()}]",
    )
    if self.buf[i] > 0x7f {
      need_conv = true
    }
    // Digest covers the NUL terminator.
    self.digest.write(self.buf[i])
    if self.buf[i] == 0 {
      // Strings are ISO 8859-1, Latin-1 (RFC 1952, section 2.3.1).
      if need_conv {
        let s = Array::new(capacity=i)
        for v in self.buf[:i] {
          s.push(Char::from_int(v.to_int()))
        }
        return String::from_array(s)
      }
      return @base64.bytes2str(Bytes::from_iter(self.buf[:i].iter()))
    }
  }
  raise fail!("unterminated string")
}

fn dump_buf(buf : @buffer.Buffer) -> String {
  buf
  .to_bytes()
  .to_array()
  .map(fn(b) { b.to_int() })
  .to_string()
  .replace_all(old=",", new="")
}

test "internal functions for converting to and from Latin-1" {
  gml_debug.val = false

  //
  let latin1 = [b'\xc4', b'u', 0xdf, b'e', b'r', b'u', b'n', b'g', 0]
  let utf16 = "Äußerung"

  //
  let buf = @buffer.Buffer::new(size_hint=latin1.length())
  buf.write_bytes(Bytes::from_array(latin1))

  //
  gmldbg("GML: TestLatin1: got=\{dump_buf(buf)}")

  //
  let r = @flate.IOReader::from_buffer(buf)
  let z = {
    header: Header::new(),
    r,
    decompressor: @flate.Reader::new(r),
    digest: @crc32.Digest::new(),
    size: 0,
    buf: latin1,
    err: None,
    multistream: false,
  }
  let s = z.read_string!()
  assert_eq!(s, utf16)
  let buf = @buffer.Buffer::new(size_hint=latin1.length())
  let w = @flate.IOWriter::from_buffer(buf)
  let c : Writer = {
    header: Header::new(),
    w,
    level: best_speed,
    wrote_header: false,
    closed: false,
    buf: [],
    compressor: @flate.Writer::new(w),
    digest: 0U,
    size: 0U,
    err: None,
  }
  c.write_string!(utf16)
  let s = buf.to_bytes().to_array()
  assert_eq!(s, latin1)
}

// readHeader reads the GZIP header according to section 2.3.1.
// This method does not set self.err.
fn read_header(self : Reader) -> Header!Error {
  gmldbg("GML: gunzip.go: (z *Reader) readHeader() (hdr Header, err error) {")
  // RFC 1952, section 2.2, says the following:
  //	A gzip file consists of a series of "members" (compressed data sets).
  //
  // Other than this, the specification does not clarify whether a
  // "series" is defined as "one or more" or "zero or more". To err on the
  // side of caution, Go interprets this to mean "zero or more".
  // Thus, it is okay to return IOEOF here.
  let hdr = Header::new()
  let (_, err) = self.r.read_full(self.buf[:10])
  match err {
    Some(e) => {
      gmldbg("GML: gunzip.go: readHeader: A: err=???")
      raise e
    }
    _ => ()
  }
  if self.buf[0] != gzip_id1 ||
    self.buf[1] != gzip_id2 ||
    self.buf[2] != gzip_deflate {
    gmldbg("GML: gunzip.go: readHeader: B: err=ErrHeader")
    raise ErrHeader
  }
  let flg = self.buf[3]
  let t = le_uint32(self.buf[4:8]).to_int64()
  if t > 0 {
    // Section 2.3.1, the zero value for MTIME means that the
    // modified time is not set.
    hdr.mod_time = Some(
      @time.PlainDateTime::from_unix_second!(t, 0, @time.utc_offset),
    )
  }
  // self.buf[8] is XFL and is currently ignored.
  hdr.os = self.buf[9]
  self.digest = @crc32.Digest::new()
  for i in 0..<10 {
    self.digest.write(self.buf[i])
  }
  gmldbg(
    "GML: readHeader: A: consumed 10 bytes from reader: \{dump_av(self.buf[:10])}",
  )

  //
  if (flg & flag_extra) != 0 {
    let (_, err) = self.r.read_full(self.buf[:2])
    match err {
      Some(e) => {
        gmldbg("GML: gunzip.go: readHeader: C: noEOF(err)=???")
        raise no_eof(e)
      }
      _ => ()
    }
    self.digest..write(self.buf[0]).write(self.buf[1])
    gmldbg(
      "GML: readHeader: B: consumed 2 bytes from reader: [\{self.buf[0].to_int()} \{self.buf[1].to_int()}]",
    )
    let data_size = le_uint16(self.buf[:2]).reinterpret_as_int()
    let data = Array::make(data_size, b'\x00')
    let (_, err) = self.r.read_full(data[:])
    match err {
      Some(e) => {
        gmldbg("GML: gunzip.go: readHeader: D: noEOF(err)=???")
        raise no_eof(e)
      }
      _ => ()
    }
    for i in 0..<data_size {
      self.digest.write(data[i])
    }
    hdr.extra = data
    gmldbg(
      "GML: readHeader: C: consumed \{data_size} bytes from reader: \{dump_av(data[:])}",
    )
  }
  if (flg & flag_name) != 0 {
    let s = try {
      self.read_string!()
    } catch {
      e => {
        gmldbg("GML: gunzip.go: readHeader: E: noEOF(err)=???")
        raise no_eof(e)
      }
    }
    hdr.name = s
  }
  if (flg & flag_comment) != 0 {
    let s = try {
      self.read_string!()
    } catch {
      e => {
        gmldbg("GML: gunzip.go: readHeader: F: noEOF(err)=???")
        raise no_eof(e)
      }
    }
    hdr.comment = s
  }
  if (flg & flag_hdr_crc) != 0 {
    let (_, err) = self.r.read_full(self.buf[:2])
    match err {
      Some(e) => {
        gmldbg("GML: gunzip.go: readHeader: G: noEOF(err)=???")
        raise no_eof(e)
      }
      _ => ()
    }
    gmldbg(
      "GML: readHeader: D: consumed 2 bytes from reader: [\{self.buf[0]} \{self.buf[1]}]",
    )
    let digest = le_uint16(self.buf[:2])
    if digest != self.digest.digest() {
      gmldbg("GML: gunzip.go: readHeader: H: err=ErrHeader")
      raise ErrHeader
    }
  }
  self.digest = @crc32.Digest::new()
  gmldbg("GML: gunzip.go: calling:  z.decompressor = flate.NewReader(z.r)")
  self.decompressor = @flate.Reader::new(self.r)
  gmldbg("GML: gunzip.go: readHeader: I: no err")
  hdr
}

fn le_uint16(b : ArrayView[Byte]) -> UInt {
  b[0].to_uint() | (b[1].to_uint() << 8)
}

fn le_uint32(b : ArrayView[Byte]) -> UInt {
  b[0].to_uint() |
  (b[1].to_uint() << 8) |
  (b[2].to_uint() << 16) |
  (b[3].to_uint() << 24)
}

// Read implements [IOReadCloser], reading uncompressed bytes from its underlying [Reader].
fn read(self : Reader, p : ArrayView[Byte]) -> Int!Error {
  gmldbg("GML: gunzip.go: (z *Reader) Read(p []byte) (n int, err error) {")
  if not(self.err.is_empty()) {
    gmldbg("GML: gunzip.go: Read: A: z.err=???")
    raise self.err.unwrap()
  }
  let mut n = 0
  while n == 0 {
    gmldbg("GML: gunzip.go: Read: START of for n == 0 loop")
    let (tmpn, err) = self.decompressor.read(p)
    n = tmpn
    self.err = err
    gmldbg(
      "GML: gunzip.go: Read: A: Got \{n} bytes from z.decompressor: \{dump_av(p[:n])}, z.err=\{self.err}",
    )
    for i in 0..<n {
      self.digest.write(p[i])
    }
    gmldbg("GML: gunzip.go: Read: A1")
    self.size += n.reinterpret_as_uint()
    gmldbg("GML: gunzip.go: Read: A2: z.size=\{self.size}")
    match self.err {
      Some(@flate.IOEOF) => ()
      // In the normal case we return here.
      None => {
        gmldbg("GML: gunzip.go: Read: B: n=\{n}, z.err=<nil>")
        return n
      }
      Some(e) => {
        gmldbg("GML: gunzip.go: Read: B: (n=\{n}), z.err=\{self.err}")
        raise e
      }
    }
    gmldbg("GML: gunzip.go: Read: B2")

    // Finished file; check checksum and size.
    let (_, err) = self.r.read_full(self.buf[:8])
    match err {
      Some(e) => {
        let e = no_eof(e)
        self.err = Some(e)
        gmldbg("GML: gunzip.go: Read: C: z.err=\{self.err}")
        raise e
      }
      _ => ()
    }
    gmldbg(
      "GML: gunzip.go: Read: B: consumed 8 bytes from reader: \{dump_av(self.buf[:8])}",
    )
    let digest = le_uint32(self.buf[:4])
    let size = le_uint32(self.buf[4:8])
    if digest != self.digest.digest() || size != self.size {
      self.err = Some(ErrChecksum)
      gmldbg("GML: gunzip.go: Read: D: z.err=ErrChecksum")
      raise ErrChecksum
    }
    self.digest = @crc32.Digest::new()
    self.size = 0

    // File is ok; check if there is another.
    if not(self.multistream) {
      gmldbg("GML: gunzip.go: Read: E: err=io.EOF")
      return n
    }
    self.err = None // Remove IOEOF
    try {
      let _ = self.read_header!()

    } catch {
      // e => raise e // return n, self.err
      e => {
        self.err = Some(e)
        gmldbg("GML: gunzip.go: Read: F: z.err=???")
        // IOEOF => return n
      }
    }
  }

  //
  gmldbg("GML: gunzip.go: Read: G: no err")
  return n
}

// Close closes the [Reader]. It does not close the underlying [io.Reader].
// In order for the GZIP checksum to be verified, the reader must be
// fully consumed until the [IOEOF].
pub fn close(self : Reader) -> Unit!Error {
  try {
    self.decompressor.close!()
  } catch {
    e => {
      gmldbg(
        "GML: gunzip.go: (z *Reader) Close() error { return z.decompressor.Close() } // err=???",
      )
      raise e
    }
  }
  gmldbg(
    "GML: gunzip.go: (z *Reader) Close() error { return z.decompressor.Close() } // err=<nil>",
  )
}
