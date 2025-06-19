// -*- compile-command: "moon test --target js > got.txt"; -*-

// This package is based on the Go implementation found here:
// https://cs.opensource.google/go/go/+/refs/tags/go1.23.0:src/compress/gzip/gzip_test.go
// which has the copyright notice:
// Copyright 2010 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

///|
typealias @io.Slice

///|
test "empty payload still forms a valid GZIP stream" {
  let buf = @io.Buffer::new()
  guard @gzip.Writer::new(buf).close() is None

  //

  //
  let (r, err) = @gzip.Reader::new(buf)
  guard err is None
  inspect(r.header.os.to_int(), content="255")

  //
  guard @io.read_all(r) is (b, None)
  inspect(b.length(), content="0")
  guard r.close() is None
}

///|
test "roundtrip gzipping and then gunzipping is the identity function" {
  let buf = @io.Buffer::new()
  let w = @gzip.Writer::new(buf)

  //
  w.header.comment = "comment"
  w.header.extra = b"extra".to_array()
  let t = @time.PlainDateTime::from_unix_second(
    100_000_000, 0, @time.utc_offset,
  )
  w.header.mod_time = Some(t)
  w.header.name = "name"
  let _ = w.write(Slice::new(b"payload".to_array()))
  guard w.close() is None

  //

  //
  let (r, err) = @gzip.Reader::new(buf)
  guard err is None
  inspect(r.header.os.to_int(), content="255")

  //
  guard @io.read_all(r) is (b, None)
  assert_eq(b.to_bytes(), b"payload")
  assert_eq(r.header.comment, "comment")
  assert_eq(r.header.extra, b"extra".to_array())
  guard r.header.mod_time is Some(t)
  assert_eq(t.to_unix_second(), 100_000_000)
  assert_eq(r.header.name, "name")
  guard r.close() is None
}

///|
test "latin1 roundtrip metadata that is representable in Latin-1 survives a round trip" {
  // (name : String, ok : Bool)
  let test_cases = [
    ("", true),
    ("ASCII is OK", true),
    ("unless it contains a NUL\u{00}", false),
    ("no matter where \u{00} occurs", false),
    ("\u{00}\u{00}\u{00}", false),
    ("Látin-1 also passes (U+00E1)", true),
    ("but LĀtin Extended-A (U+0100) does not", false),
    ("neither does 日本語", false),
    ("\u{00} as does Látin-1 with NUL", false),
  ]
  for tc in test_cases {
    let buf = @io.Buffer::new()

    //
    let w = @gzip.Writer::new(buf)
    w.header.name = tc.0
    let err = w.close()
    if (err == None) != tc.1 {
      abort("Writer.Close: name = '\{tc.0}', err = \{err}")
    }
    if not(tc.1) {
      continue
    }

    //
    guard @gzip.Reader::new(buf) is (r, None)
    let _ = @io.read_all(r)
    assert_eq(r.header.name, tc.0)
    guard r.close() is None
  }
}

///|
test "writer flush" {
  let buf = @io.Buffer::new()

  //
  let w = @gzip.Writer::new(buf)
  w.header.comment = "comment"
  w.header.extra = b"extra".to_array()
  let t = @time.PlainDateTime::from_unix_second(
    100_000_000, 0, @time.utc_offset,
  )
  w.header.mod_time = Some(t)
  w.header.name = "name"

  // no data after first flush
  assert_eq(buf.to_bytes().length(), 0)

  //
  guard w.flush() is None

  // expect data after first flush
  assert_eq(buf.to_bytes().length(), 30)

  //
  guard w.write(Slice::new([b'x'])) is (n, None)
  assert_eq(n, 1)

  //
  // after writing a single byte, want no change to size
  assert_eq(buf.to_bytes().length(), 30)

  //
  guard w.flush() is None

  // since the simplified flate compressor has no flush, there is no change.
  assert_eq(buf.to_bytes().length(), 30)

  //
  guard w.close() is None

  // final output should match after flush
  assert_eq(buf.to_bytes().length(), 50)
}

///|
test "multiple gzip files concatenated form a valid gzip file" {
  let buf = @io.Buffer::new()
  let w = @gzip.Writer::new(buf)
  guard w.write(Slice::new(b"hello ".to_array())) is (_, None)
  guard w.close() is None
  let w = @gzip.Writer::new(buf)
  guard w.write(Slice::new(b"world\n".to_array())) is (_, None)
  guard w.close() is None

  //
  let (r, err) = @gzip.Reader::new(buf)
  guard err is None
  guard @io.read_all(r) is (data, None)
  assert_eq(data.to_bytes(), b"hello world\n")
}
