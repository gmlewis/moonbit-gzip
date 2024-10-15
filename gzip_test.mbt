// -*- compile-command: "moon test --target js > got.txt"; -*-

// This package is based on the Go implementation found here:
// https://cs.opensource.google/go/go/+/refs/tags/go1.23.0:src/compress/gzip/gzip_test.go
// which has the copyright notice:
// Copyright 2010 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

let broken : Map[Int, Bool] = { 20: true }

test "empty payload still forms a valid GZIP stream" {
  @gzip.gml_debug.val = broken[0].or_default()

  //
  let buf = @buffer.Buffer::new()
  @gzip.Writer::new(@flate.IOWriter::from_buffer(buf)).close!()

  //
  @gzip.gmldbg("GML: TestEmpty: got=\{dump_buf(buf)}")

  //
  let r = @gzip.Reader::new!(@flate.IOReader::from_buffer(buf))
  inspect!(r.header.os.to_int(), content="255")

  //
  let b = r.read_all!()
  inspect!(b.length(), content="0")
  r.close!()
}

fn dump_buf(buf : @buffer.Buffer) -> String {
  buf
  .to_bytes()
  .to_array()
  .map(fn(b) { b.to_int() })
  .to_string()
  .replace_all(old=",", new="")
}

test "roundtrip gzipping and then gunzipping is the identity function" {
  @gzip.gml_debug.val = broken[1].or_default()

  //
  let buf = @buffer.Buffer::new()
  let w = @gzip.Writer::new(@flate.IOWriter::from_buffer(buf))

  //
  w.header.comment = "comment"
  w.header.extra = b"extra".to_array()
  let t = @time.PlainDateTime::from_unix_second!(
    100_000_000, 0, @time.utc_offset,
  )
  w.header.mod_time = Some(t)
  w.header.name = "name"
  let _ = w.write!(b"payload".to_array()[:])
  w.close!()

  //
  @gzip.gmldbg("GML: TestRoundTrip: got=\{dump_buf(buf)}")

  //
  let r = @gzip.Reader::new!(@flate.IOReader::from_buffer(buf))
  inspect!(r.header.os.to_int(), content="255")

  //
  let b = r.read_all!()
  assert_eq!(b, b"payload")
  assert_eq!(r.header.comment, "comment")
  assert_eq!(r.header.extra, b"extra".to_array())
  guard let Some(t) = r.header.mod_time
  assert_eq!(t.to_unix_second(), 100_000_000)
  assert_eq!(r.header.name, "name")
  r.close!()
}

test "latin1 roundtrip metadata that is representable in Latin-1 survives a round trip" {
  @gzip.gml_debug.val = broken[2].or_default()

  // (name : String, ok : Bool)
  let test_cases = [
    ("", true),
    ("ASCII is OK", true),
    ("unless it contains a NUL\x00", false),
    ("no matter where \x00 occurs", false),
    ("\x00\x00\x00", false),
    ("Látin-1 also passes (U+00E1)", true),
    ("but LĀtin Extended-A (U+0100) does not", false),
    ("neither does 日本語", false),
    ("invalid UTF-8 also \xffails", false),
    ("\x00 as does Látin-1 with NUL", false),
  ]
  for tc in test_cases {
    @gzip.gmldbg("test '\{tc.0}', tc.1=\{tc.1}...")
    let buf = @buffer.Buffer::new()

    //
    let w = @gzip.Writer::new(@flate.IOWriter::from_buffer(buf))
    w.header.name = tc.0
    try {
      w.close!()
      if not(tc.1) {
        @gzip.gmldbg("@gzip.Writer.close: name='\{tc.0}', got ok, want error")
      }
      assert_true!(tc.1)
    } catch {
      _ => {
        if tc.1 {
          @gzip.gmldbg("@gzip.Writer.close: name='\{tc.0}', got error, want ok")
        }
        assert_false!(tc.1)
      }
    }
    if not(tc.1) {
      continue
    }

    //
    @gzip.gmldbg(
      "GML: TestLatin1RoundTrip: name='\{tc.0}', got=\{dump_buf(buf)}",
    )

    //
    let r = @gzip.Reader::new!(@flate.IOReader::from_buffer(buf))
    let _ = r.read_all!()
    assert_eq!(r.header.name, tc.0)
    r.close!()
  }
}

test "writer flush" {
  let buf = @buffer.Buffer::new()

  //
  let w = @gzip.Writer::new(@flate.IOWriter::from_buffer(buf))
  w.header.comment = "comment"
  w.header.extra = b"extra".to_array()
  let t = @time.PlainDateTime::from_unix_second!(
    100_000_000, 0, @time.utc_offset,
  )
  w.header.mod_time = Some(t)
  w.header.name = "name"

  // no data after first flush
  assert_eq!(buf.to_bytes().length(), 0)

  //
  w.flush!()

  // expect data after first flush
  assert_eq!(buf.to_bytes().length(), 30)

  //
  let n = w.write!([b'x'][:])
  assert_eq!(n, 1)

  //
  // after writing a single byte, want no change to size
  assert_eq!(buf.to_bytes().length(), 30)

  //
  w.flush!()

  // since the simplified flate compressor has no flush, there is no change.
  assert_eq!(buf.to_bytes().length(), 30)

  //
  w.close!()

  // final output should match after flush
  assert_eq!(buf.to_bytes().length(), 50)
}

test "multiple gzip files concatenated form a valid gzip file" {
  let buf = @buffer.Buffer::new()
  let w = @gzip.Writer::new(@flate.IOWriter::from_buffer(buf))
  let _ = w.write!(b"hello ".to_array()[:])
  w.close!()
  let w = @gzip.Writer::new(@flate.IOWriter::from_buffer(buf))
  let _ = w.write!(b"world\n".to_array()[:])
  w.close!()

  //
  let r = @gzip.Reader::new!(@flate.IOReader::from_buffer(buf))
  let data = r.read_all!()
  assert_eq!(data, b"hello world\n")
}

// type limitedWriter struct {
// 	N int
// }

// func (l *limitedWriter) Write(p []byte) (n int, err error) {
// 	if n := l.N; n < len(p) {
// 		l.N = 0
// 		return n, io.ErrShortWrite
// 	}
// 	l.N -= len(p)
// 	return len(p), nil
// }

// test "write should never return more bytes than the input slice" {
// 	msg := []byte("a")

// 	for lim := 2; lim < 20; lim++ {
// 		z := NewWriter(&limitedWriter{lim})
// 		if n, _ := z.Write(msg); n > len(msg) {
// 			t.Errorf("Write() = %d, want %d or less", n, len(msg))
// 		}

// 		z.Reset(&limitedWriter{lim})
// 		z.Header = Header{
// 			Comment: "comment",
// 			Extra:   []byte("extra"),
// 			ModTime: time.Now(),
// 			Name:    "name",
// 			OS:      1,
// 		}
// 		if n, _ := z.Write(msg); n > len(msg) {
// 			t.Errorf("Write() = %d, want %d or less", n, len(msg))
// 		}
// 	}
// }
