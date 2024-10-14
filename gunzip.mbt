// This package is based on the Go implementation found here:
// https://cs.opensource.google/go/go/+/refs/tags/go1.23.0:src/compress/gzip/gunzip.go
// which has the copyright notice:
// Copyright 2009 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

let gzip_id1 = b'\x1f'

let gzip_id2 = b'\x8b'

let gzip_deflate : Byte = b'\x08'

let flag_text : Byte = b'\x01'

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

// no_eof converts io.EOF to io.ErrUnexpectedEOF.
fn no_eof(err : Error) -> Error {
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
  comment : String // comment
  extra : Bytes? // "extra data"
  mod_time : @time.PlainDateTime? // modification time
  name : String // file name
  os : Byte // operating system type
}

pub fn Header::new() -> Header {
  { comment: "", extra: None, mod_time: None, name: "", os: b'\xff' }
}

// A Reader is a [@flat.IOReader] that can be read to retrieve
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
// returned by [Reader.Read] as tentative until they receive the [io.EOF]
// marking the end of the data.
pub struct Reader {
  header : Header // valid after NewReader or Reader.Reset
  priv mut r : @flate.IOReader
  priv mut decompressor : @flate.IOReadCloser
  priv mut digest : @crc32.Digest // CRC-32, IEEE polynomial (section 8)
  priv mut size : UInt // Uncompressed size (section 2.3.1)
  priv mut buf : Array[Byte] // [512]byte
  priv mut err : Error?
  priv mut multistream : Bool
}

// NewReader creates a new [Reader] reading the given reader.
// If r does not also implement [io.ByteReader],
// the decompressor may read more data than necessary from r.
//
// It is the caller's responsibility to call Close on the [Reader] when done.
//
// The [Reader.Header] fields will be valid in the [Reader] returned.
fn Reader::new(r : @flate.IOReader) -> Reader!Error {
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
  z.reset!(r)
}

// Reset discards the [Reader] z's state and makes it equivalent to the
// result of its original state from [NewReader], but reading from r instead.
// This permits reusing a [Reader] rather than allocating a new one.
fn reset(self : Reader, r : @flate.IOReader) -> Reader!Error {
  self.r = r
  self.digest = @crc32.Digest::new()
  self.size = 0
  self.buf = Array::make(512, b'\x00')
  self.err = None
  self.multistream = true
  self.header = self.read_header!()
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
// [Reader.Read] returns [io.EOF]. The underlying reader must implement [io.ByteReader]
// in order to be left positioned just after the gzip stream.
// To start the next stream, call z.Reset(r) followed by z.Multistream(false).
// If there is no next stream, z.Reset(r) will return [io.EOF].
pub fn multistream(self : Reader, ok : Bool) -> Unit {
  self.multistream = ok
}

// readString reads a NUL-terminated string from z.r.
// It treats the bytes read as being encoded as ISO 8859-1 (Latin-1) and
// will output a string encoded using UTF-8.
// This method always updates z.digest with the data read.
fn read_string(self : Reader) -> String!Error {
  let mut err : Error? = None
  let mut need_conv = false
  for i = 0; true; i = i + 1 {
    if i >= self.buf.length() {
      raise ErrHeader
    }
    self.buf[i] = self.r.read_byte!()
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
      return "TODO"
    }
  }
  raise fail!("unterminated string")
}

// // readHeader reads the GZIP header according to section 2.3.1.
// // This method does not set z.err.
// func (z *Reader) readHeader() (hdr Header, err error) {
// 	if _, err = io.ReadFull(z.r, z.buf[:10]); err != nil {
// 		// RFC 1952, section 2.2, says the following:
// 		//	A gzip file consists of a series of "members" (compressed data sets).
// 		//
// 		// Other than this, the specification does not clarify whether a
// 		// "series" is defined as "one or more" or "zero or more". To err on the
// 		// side of caution, Go interprets this to mean "zero or more".
// 		// Thus, it is okay to return io.EOF here.
// 		return hdr, err
// 	}
// 	if z.buf[0] != gzipID1 || z.buf[1] != gzipID2 || z.buf[2] != gzipDeflate {
// 		return hdr, ErrHeader
// 	}
// 	flg := z.buf[3]
// 	if t := int64(le.Uint32(z.buf[4:8])); t > 0 {
// 		// Section 2.3.1, the zero value for MTIME means that the
// 		// modified time is not set.
// 		hdr.ModTime = time.Unix(t, 0)
// 	}
// 	// z.buf[8] is XFL and is currently ignored.
// 	hdr.OS = z.buf[9]
// 	z.digest = crc32.ChecksumIEEE(z.buf[:10])

// 	if flg&flagExtra != 0 {
// 		if _, err = io.ReadFull(z.r, z.buf[:2]); err != nil {
// 			return hdr, no_eof(err)
// 		}
// 		z.digest = crc32.Update(z.digest, crc32.IEEETable, z.buf[:2])
// 		data := make([]byte, le.Uint16(z.buf[:2]))
// 		if _, err = io.ReadFull(z.r, data); err != nil {
// 			return hdr, no_eof(err)
// 		}
// 		z.digest = crc32.Update(z.digest, crc32.IEEETable, data)
// 		hdr.Extra = data
// 	}

// 	var s string
// 	if flg&flagName != 0 {
// 		if s, err = z.readString(); err != nil {
// 			return hdr, no_eof(err)
// 		}
// 		hdr.Name = s
// 	}

// 	if flg&flagComment != 0 {
// 		if s, err = z.readString(); err != nil {
// 			return hdr, no_eof(err)
// 		}
// 		hdr.Comment = s
// 	}

// 	if flg&flagHdrCrc != 0 {
// 		if _, err = io.ReadFull(z.r, z.buf[:2]); err != nil {
// 			return hdr, no_eof(err)
// 		}
// 		digest := le.Uint16(z.buf[:2])
// 		if digest != uint16(z.digest) {
// 			return hdr, ErrHeader
// 		}
// 	}

// 	z.digest = 0
// 	if z.decompressor == nil {
// 		z.decompressor = flate.NewReader(z.r)
// 	} else {
// 		z.decompressor.(flate.Resetter).Reset(z.r, nil)
// 	}
// 	return hdr, nil
// }

// // Read implements [io.Reader], reading uncompressed bytes from its underlying [Reader].
// func (z *Reader) Read(p []byte) (n int, err error) {
// 	if z.err != nil {
// 		return 0, z.err
// 	}

// 	for n == 0 {
// 		n, z.err = z.decompressor.Read(p)
// 		z.digest = crc32.Update(z.digest, crc32.IEEETable, p[:n])
// 		z.size += uint32(n)
// 		if z.err != io.EOF {
// 			// In the normal case we return here.
// 			return n, z.err
// 		}

// 		// Finished file; check checksum and size.
// 		if _, err := io.ReadFull(z.r, z.buf[:8]); err != nil {
// 			z.err = no_eof(err)
// 			return n, z.err
// 		}
// 		digest := le.Uint32(z.buf[:4])
// 		size := le.Uint32(z.buf[4:8])
// 		if digest != z.digest || size != z.size {
// 			z.err = ErrChecksum
// 			return n, z.err
// 		}
// 		z.digest, z.size = 0, 0

// 		// File is ok; check if there is another.
// 		if !z.multistream {
// 			return n, io.EOF
// 		}
// 		z.err = nil // Remove io.EOF

// 		if _, z.err = z.readHeader(); z.err != nil {
// 			return n, z.err
// 		}
// 	}

// 	return n, nil
// }

// // Close closes the [Reader]. It does not close the underlying [io.Reader].
// // In order for the GZIP checksum to be verified, the reader must be
// // fully consumed until the [io.EOF].
// func (z *Reader) Close() error { return z.decompressor.Close() }
