// -*- compile-command: "moon test --target js > got.txt"; -*-

// This package is based on the Go implementation found here:
// https://cs.opensource.google/go/go/+/refs/tags/go1.23.0:src/compress/gzip/gunzip.go
// which has the copyright notice:
// Copyright 2009 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

///|
let gzip_id1 = b'\x1f'

///|
let gzip_id2 = b'\x8b'

///|
let gzip_deflate : Byte = b'\x08'

// let flag_text : Byte = b'\x01'

///|
let flag_hdr_crc : Byte = b'\x02'

///|
let flag_extra : Byte = b'\x04'

///|
let flag_name : Byte = b'\x08'

///|
let flag_comment : Byte = b'\x10'

// var le = binary.LittleEndian

///|
typealias @io.Slice

///|
typealias @io.IOError

///|
/// err_checksum is returned when reading GZIP data that has an invalid checksum.
pub let err_checksum : IOError = IOError("gzip: invalid checksum")

///|
/// err_header is returned when reading GZIP data that has an invalid header.
pub let err_header : IOError = IOError("gzip: invalid header")

///|
pub let err_unexpected_eof : IOError = @io.err_unexpected_eof

///|
pub let ioeof : IOError = @io.eof

///|
/// no_eof converts ioeof to io.err_unexpected_eof.
fn no_eof(err : IOError) -> IOError {
  if ioeof == err {
    return err_unexpected_eof
  }
  err
}

///|
/// The gzip file stores a header giving metadata about the compressed file.
/// That header is exposed as the fields of the [Writer] and [Reader] structs.
///
/// Strings must be UTF-8 encoded and may only contain Unicode code points
/// U+0001 through U+00FF, due to limitations of the GZIP file format.
pub(all) struct Header {
  mut comment : String // comment
  mut extra : Array[Byte] // "extra data"
  mut mod_time : @time.PlainDateTime? // modification time
  mut name : String // file name
  mut os : Byte // operating system type
}

///|
pub fn Header::new() -> Header {
  { comment: "", extra: [], mod_time: None, name: "", os: b'\xff' }
}

///|
/// A Reader is an [IOReadCloser] that can be read to retrieve
/// uncompressed data from a gzip-format compressed file.
///
/// In general, a gzip file can be a concatenation of gzip files,
/// each with its own header. Reads from the Reader
/// return the concatenation of the uncompressed data of each.
/// Only the first header is recorded in the Reader fields.
///
/// Gzip files store a length and checksum of the uncompressed data.
/// The Reader will return an [err_checksum] when [Reader.Read]
/// reaches the end of the uncompressed data if it does not
/// have the expected length or checksum. Clients should treat data
/// returned by [Reader.Read] as tentative until they receive the [ioeof]
/// marking the end of the data.
pub(all) struct Reader {
  mut header : Header // valid after NewReader or Reader.Reset
  priv mut r : &@flate.Reader
  priv mut decompressor : &@io.ReadCloser
  priv mut digest : @crc32.Digest // CRC-32, IEEE polynomial (section 8)
  priv mut size : UInt // Uncompressed size (section 2.3.1)
  priv mut buf : Array[Byte] // [512]byte
  priv mut err : IOError?
  priv mut multistream : Bool
}

///|
/// Reader implements the &io.Reader and &io.ReadCloser traits.
let _trait1 : &@io.Reader = Reader::new(@io.Buffer::new()).0

///|
let _trait2 : &@io.ReadCloser = Reader::new(@io.Buffer::new()).0

///|
/// NewReader creates a new [IOReader] reading the given reader.
///
/// It is the caller's responsibility to call Close on the [Reader] when done.
///
/// The [Reader.Header] fields will be valid in the [Reader] returned.
pub fn Reader::new(r : &@flate.Reader) -> (Reader, IOError?) {
  let z = {
    header: Header::new(),
    r,
    decompressor: &@flate.Reader::new(r),
    digest: @crc32.Digest::new(),
    size: 0,
    buf: [],
    err: None,
    multistream: false,
  }
  let err = z.reset(r)
  return (z, err)
}

///|
/// Reset discards the [Reader] z's state and makes it equivalent to the
/// result of its original state from [NewReader], but reading from r instead.
/// This permits reusing a [Reader] rather than allocating a new one.
pub fn reset(self : Reader, r : &@flate.Reader) -> IOError? {
  self.r = r
  self.digest = @crc32.Digest::new()
  self.size = 0
  self.buf = Array::make(512, b'\x00')
  self.multistream = true
  let (header, err) = self.read_header()
  self.header = header
  self.err = err
  return self.err
}

///|
/// Multistream controls whether the reader supports multistream files.
///
/// If enabled (the default), the [Reader] expects the input to be a sequence
/// of individually gzipped data streams, each with its own header and
/// trailer, ending at EOF. The effect is that the concatenation of a sequence
/// of gzipped files is treated as equivalent to the gzip of the concatenation
/// of the sequence. This is standard behavior for gzip readers.
///
/// Calling Multistream(false) disables this behavior; disabling the behavior
/// can be useful when reading file formats that distinguish individual gzip
/// data streams or mix gzip data streams with other data streams.
/// In this mode, when the [Reader] reaches the end of the data stream,
/// [Reader.Read] returns [ioeof]. The underlying reader must implement [io.ByteReader]
/// in order to be left positioned just after the gzip stream.
/// To start the next stream, call self.Reset(r) followed by self.Multistream(false).
/// If there is no next stream, self.Reset(r) will return [ioeof].
pub fn multistream(self : Reader, ok : Bool) -> Unit {
  self.multistream = ok
}

///|
/// read_string reads a NUL-terminated string from self.r.
/// It treats the bytes read as being encoded as ISO 8859-1 (Latin-1) and
/// will output a MoonBit String encoded using UTF-16.
/// This method always updates self.digest with the data read.
fn read_string(self : Reader) -> (String, IOError?) {
  let mut need_conv = false
  for i = 0; true; i = i + 1 {
    if i >= self.buf.length() {
      return ("", Some(err_header))
    }
    let (b, err) = self.r.read_byte()
    match err {
      Some(_) => return ("", err)
      _ => ()
    }
    self.buf[i] = b
    if self.buf[i] > 0x7f {
      need_conv = true
    }
    // Digest covers the NUL terminator, so _all_ bytes are written to the digest:
    self.digest.write(self.buf[i])
    if self.buf[i] == 0 {
      // Strings are ISO 8859-1, Latin-1 (RFC 1952, section 2.3.1).
      if need_conv {
        let s = Array::new(capacity=i)
        for v in self.buf[:i] {
          s.push(Int::unsafe_to_char(v.to_int()))
        }
        return (String::from_array(s), None)
      }
      return (@base64.bytes2str(Bytes::from_iter(self.buf[:i].iter())), None)
    }
  }
  (
    "",
    Some(
      IOError("gunzip.mbt: read_string: unexpected error: unterminated string"),
    ),
  )
}

///|
test "internal functions for converting to and from Latin-1" {
  let latin1 = [b'\xc4', b'u', 0xdf, b'e', b'r', b'u', b'n', b'g', 0]
  let utf16 = "Äußerung"

  //
  let r = @io.Buffer::new()
  guard r.write_bytes(Bytes::from_array(latin1)) is (_, None)

  //

  //
  let z = {
    header: Header::new(),
    r,
    decompressor: &@flate.Reader::new(r),
    digest: @crc32.Digest::new(),
    size: 0,
    buf: latin1,
    err: None,
    multistream: false,
  }
  guard z.read_string() is (s, None)
  assert_eq(s, utf16)
  let w = @io.Buffer::new()
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
  guard c.write_string(utf16) is None
  let s = w.to_bytes().to_array()
  assert_eq(s, latin1)
}

///|
/// read_header reads the GZIP header according to section 2.3.1.
/// This method does not set self.err.
fn read_header(self : Reader) -> (Header, IOError?) {
  // RFC 1952, section 2.2, says the following:
  //	A gzip file consists of a series of "members" (compressed data sets).
  //
  // Other than this, the specification does not clarify whether a
  // "series" is defined as "one or more" or "zero or more". To err on the
  // side of caution, Go interprets this to mean "zero or more".
  // Thus, it is okay to return ioeof here.
  let hdr = Header::new()
  let (_, err) = @io.read_full(self.r, Slice::new(self.buf)[:10])
  match err {
    Some(_) => return (hdr, err)
    _ => ()
  }
  if self.buf[0] != gzip_id1 ||
    self.buf[1] != gzip_id2 ||
    self.buf[2] != gzip_deflate {
    return (hdr, Some(err_header))
  }
  let flg = self.buf[3]
  let t = le_uint32(self.buf[4:8]).to_int64()
  if t > 0 {
    // Section 2.3.1, the zero value for MTIME means that the
    // modified time is not set.
    try {
      let mod_time = @time.PlainDateTime::from_unix_second(
        t, 0, @time.utc_offset,
      )
      hdr.mod_time = Some(mod_time)
    } catch {
      _ => ()
    }
  }
  // self.buf[8] is XFL and is currently ignored.
  hdr.os = self.buf[9]
  self.digest = @crc32.Digest::new()
  for i in 0..<10 {
    self.digest.write(self.buf[i])
  }

  //
  if (flg & flag_extra) != 0 {
    let (_, err) = @io.read_full(self.r, Slice::new(self.buf)[:2])
    match err {
      Some(e) => return (hdr, Some(no_eof(e)))
      _ => ()
    }
    self.digest..write(self.buf[0]).write(self.buf[1])
    let data_size = le_uint16(self.buf[:2]).reinterpret_as_int()
    let data = Array::make(data_size, b'\x00')
    let (_, err) = @io.read_full(self.r, Slice::new(data))
    match err {
      Some(e) => return (hdr, Some(no_eof(e)))
      _ => ()
    }
    for i in 0..<data_size {
      self.digest.write(data[i])
    }
    hdr.extra = data
  }

  //
  if (flg & flag_name) != 0 {
    let (s, err) = self.read_string()
    guard err is None else { return (hdr, Some(no_eof(err.unwrap()))) }
    hdr.name = s
  }

  //
  if (flg & flag_comment) != 0 {
    let (s, err) = self.read_string()
    guard err is None else { return (hdr, Some(no_eof(err.unwrap()))) }
    hdr.comment = s
  }

  //
  if (flg & flag_hdr_crc) != 0 {
    let (_, err) = @io.read_full(self.r, Slice::new(self.buf)[:2])
    match err {
      Some(e) => return (hdr, Some(no_eof(e)))
      _ => ()
    }
    let digest = le_uint16(self.buf[:2])
    let z_digest = self.digest.digest() & 0xffff
    if digest != z_digest {
      return (hdr, Some(err_header))
    }
  }

  //
  self.digest = @crc32.Digest::new()
  self.decompressor = &@flate.Reader::new(self.r)
  (hdr, None)
}

///|
fn le_uint16(b : ArrayView[Byte]) -> UInt {
  b[0].to_uint() | (b[1].to_uint() << 8)
}

///|
fn le_uint32(b : ArrayView[Byte]) -> UInt {
  b[0].to_uint() |
  (b[1].to_uint() << 8) |
  (b[2].to_uint() << 16) |
  (b[3].to_uint() << 24)
}

///|
/// Read implements [IOReadCloser], reading uncompressed bytes from its underlying [Reader].
pub impl @io.Reader for Reader with read(self, p) {
  if not(self.err.is_empty()) {
    return (0, self.err)
  }

  //
  let mut n = 0
  while n == 0 {
    let (tmpn, err) = self.decompressor.read(p)
    n = tmpn
    self.err = err
    for i in 0..<n {
      self.digest.write(p[i])
    }
    self.size += n.reinterpret_as_uint()
    if Some(ioeof) != self.err {
      // In the normal case we return here.
      return (n, self.err)
    }

    // Finished file; check checksum and size.
    let (_, err) = @io.read_full(self.r, Slice::new(self.buf)[:8])
    match err {
      Some(e) => {
        self.err = Some(no_eof(e))
        return (n, self.err)
      }
      _ => ()
    }
    let digest = le_uint32(self.buf[:4])
    let size = le_uint32(self.buf[4:8])
    if digest != self.digest.digest() || size != self.size {
      self.err = Some(err_checksum)
      return (n, self.err)
    }
    self.digest = @crc32.Digest::new()
    self.size = 0

    // File is ok; check if there is another.
    if not(self.multistream) {
      return (n, Some(ioeof))
    }
    self.err = None // Remove ioeof

    //
    let (_, err) = self.read_header()
    self.err = err
    match err {
      Some(_) => return (n, self.err)
      _ => ()
    }
  }

  //
  return (n, None)
}

///|
/// Close closes the [Reader]. It does not close the underlying [io.Reader].
/// In order for the GZIP checksum to be verified, the reader must be
/// fully consumed until the [ioeof].
pub impl @io.Closer for Reader with close(self) {
  self.decompressor.close()
}
