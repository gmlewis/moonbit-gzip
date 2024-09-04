/// This package is based on the Go implementation found here:
/// https://cs.opensource.google/go/go/+/refs/tags/go1.23.0:src/compress/gzip/gunzip.go
/// which has the copyright notice:
/// Copyright 2009 The Go Authors. All rights reserved.
/// Use of this source code is governed by a BSD-style
/// license that can be found in the LICENSE file.

let gzip_id1 = b'\x1f'

let gzip_id2 = b'\x8b'

let gzip_deflate : Byte = b'\x08'

let flag_text : Byte = b'\x01'

let flag_hdr_crc : Byte = b'\x02'

let flag_extra : Byte = b'\x04'

let flag_name : Byte = b'\x08'

let flag_comment : Byte = b'\x10'

pub type! ErrorChecksum

pub type! ErrorHeader

pub type! ErrorNoEOF

/// The gzip file stores a header giving metadata about the compressed file.
/// That header is exposed as the fields of the [Writer] and [Reader] structs.
///
/// Strings must be UTF-8 encoded and may only contain Unicode code points
/// U+0001 through U+00FF, due to limitations of the GZIP file format.
pub struct Header {
  comment : String // comment
  extra : Bytes? // "extra data"
  mod_time : @wallClock.DateTime? // modification time
  name : String // file name
  os : Byte // operating system type
}

pub fn Header::new() -> Header {
  { comment: "", extra: None, mod_time: "", name: "", os: b'\xff' }
}
