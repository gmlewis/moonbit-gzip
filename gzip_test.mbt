// -*- compile-command: "moon test --target js > got.txt"; -*-

// This package is based on the Go implementation found here:
// https://cs.opensource.google/go/go/+/refs/tags/go1.23.0:src/compress/gzip/gzip_test.go
// which has the copyright notice:
// Copyright 2010 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

let broken : Map[Int, Bool] = { 1: false }

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

// test "internal functions for converting to and from Latin-1" {
// 	latin1 := []byte{0xc4, 'u', 0xdf, 'e', 'r', 'u', 'n', 'g', 0}
// 	utf8 := "Äußerung"
// 	z := Reader{r: bufio.NewReader(bytes.NewReader(latin1))}
// 	s, err := z.readString()
// 	if err != nil {
// 		t.Fatalf("readString: %v", err)
// 	}
// 	if s != utf8 {
// 		t.Fatalf("read latin-1: got %q, want %q", s, utf8)
// 	}

// 	buf := bytes.NewBuffer(make([]byte, 0, len(latin1)))
// 	c := Writer{w: buf}
// 	if err = c.writeString(utf8); err != nil {
// 		t.Fatalf("writeString: %v", err)
// 	}
// 	s = buf.String()
// 	if s != string(latin1) {
// 		t.Fatalf("write utf-8: got %q, want %q", s, string(latin1))
// 	}
// }

// test "metadata that is representable in Latin-1 survives a round trip" {
// 	testCases := []struct {
// 		name string
// 		ok   bool
// 	}{
// 		{"", true},
// 		{"ASCII is OK", true},
// 		{"unless it contains a NUL\x00", false},
// 		{"no matter where \x00 occurs", false},
// 		{"\x00\x00\x00", false},
// 		{"Látin-1 also passes (U+00E1)", true},
// 		{"but LĀtin Extended-A (U+0100) does not", false},
// 		{"neither does 日本語", false},
// 		{"invalid UTF-8 also \xffails", false},
// 		{"\x00 as does Látin-1 with NUL", false},
// 	}
// 	for _, tc := range testCases {
// 		buf := new(bytes.Buffer)

// 		w := NewWriter(buf)
// 		w.Name = tc.name
// 		err := w.Close()
// 		if (err == nil) != tc.ok {
// 			t.Errorf("Writer.Close: name = %q, err = %v", tc.name, err)
// 			continue
// 		}
// 		if !tc.ok {
// 			continue
// 		}

// 		r, err := NewReader(buf)
// 		if err != nil {
// 			t.Errorf("NewReader: %v", err)
// 			continue
// 		}
// 		_, err = io.ReadAll(r)
// 		if err != nil {
// 			t.Errorf("ReadAll: %v", err)
// 			continue
// 		}
// 		if r.Name != tc.name {
// 			t.Errorf("name is %q, want %q", r.Name, tc.name)
// 			continue
// 		}
// 		if err := r.Close(); err != nil {
// 			t.Errorf("Reader.Close: %v", err)
// 			continue
// 		}
// 	}
// }

// func TestWriterFlush(t *testing.T) {
// 	buf := new(bytes.Buffer)

// 	w := NewWriter(buf)
// 	w.Comment = "comment"
// 	w.Extra = []byte("extra")
// 	w.ModTime = time.Unix(1e8, 0)
// 	w.Name = "name"

// 	n0 := buf.Len()
// 	if n0 != 0 {
// 		t.Fatalf("buffer size = %d before writes; want 0", n0)
// 	}

// 	if err := w.Flush(); err != nil {
// 		t.Fatal(err)
// 	}

// 	n1 := buf.Len()
// 	if n1 == 0 {
// 		t.Fatal("no data after first flush")
// 	}

// 	w.Write([]byte("x"))

// 	n2 := buf.Len()
// 	if n1 != n2 {
// 		t.Fatalf("after writing a single byte, size changed from %d to %d; want no change", n1, n2)
// 	}

// 	if err := w.Flush(); err != nil {
// 		t.Fatal(err)
// 	}

// 	n3 := buf.Len()
// 	if n2 == n3 {
// 		t.Fatal("Flush didn't flush any data")
// 	}

// 	if err := w.Close(); err != nil {
// 		t.Fatal(err)
// 	}

// }

// test "multiple gzip files concatenated form a valid gzip file" {
// 	var buf bytes.Buffer
// 	w := NewWriter(&buf)
// 	w.Write([]byte("hello "))
// 	w.Close()
// 	w = NewWriter(&buf)
// 	w.Write([]byte("world\n"))
// 	w.Close()

// 	r, err := NewReader(&buf)
// 	if err != nil {
// 		t.Fatal(err)
// 	}
// 	data, err := io.ReadAll(r)
// 	if string(data) != "hello world\n" || err != nil {
// 		t.Fatalf("ReadAll = %q, %v, want %q, nil", data, err, "hello world")
// 	}
// }

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
