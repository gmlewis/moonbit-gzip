// This package is based on the Go implementation found here:
// https://cs.opensource.google/go/go/+/refs/tags/go1.23.0:src/compress/gzip/gzip_test.go
// which has the copyright notice:
// Copyright 2010 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

test "empty payload still forms a valid GZIP stream" {
  let in_buf = @buffer.Buffer::new()
  @gzip.Writer::new(@flate.IOWriter::from_buffer(in_buf)).close!()

  //
  let out_buf = @buffer.Buffer::new()
  let r = @gzip.Reader::new!(@flate.IOReader::from_buffer(out_buf))
  // r, err := NewReader(buf)
  // if err != nil {
  // 	t.Fatalf("NewReader: %v", err)
  // }
  // if want := (Header{OS: 255}); !reflect.DeepEqual(r.Header, want) {
  // 	t.Errorf("Header mismatch:\ngot  %#v\nwant %#v", r.Header, want)
  // }
  // b, err := io.ReadAll(r)
  // if err != nil {
  // 	t.Fatalf("ReadAll: %v", err)
  // }
  // if len(b) != 0 {
  // 	t.Fatalf("got %d bytes, want 0", len(b))
  // }
  // if err := r.Close(); err != nil {
  // 	t.Fatalf("Reader.Close: %v", err)
  // }
}

// test "gzipping and then gunzipping is the identity function" {
// 	buf := new(bytes.Buffer)

// 	w := NewWriter(buf)
// 	w.Comment = "comment"
// 	w.Extra = []byte("extra")
// 	w.ModTime = time.Unix(1e8, 0)
// 	w.Name = "name"
// 	if _, err := w.Write([]byte("payload")); err != nil {
// 		t.Fatalf("Write: %v", err)
// 	}
// 	if err := w.Close(); err != nil {
// 		t.Fatalf("Writer.Close: %v", err)
// 	}

// 	r, err := NewReader(buf)
// 	if err != nil {
// 		t.Fatalf("NewReader: %v", err)
// 	}
// 	b, err := io.ReadAll(r)
// 	if err != nil {
// 		t.Fatalf("ReadAll: %v", err)
// 	}
// 	if string(b) != "payload" {
// 		t.Fatalf("payload is %q, want %q", string(b), "payload")
// 	}
// 	if r.Comment != "comment" {
// 		t.Fatalf("comment is %q, want %q", r.Comment, "comment")
// 	}
// 	if string(r.Extra) != "extra" {
// 		t.Fatalf("extra is %q, want %q", r.Extra, "extra")
// 	}
// 	if r.ModTime.Unix() != 1e8 {
// 		t.Fatalf("mtime is %d, want %d", r.ModTime.Unix(), uint32(1e8))
// 	}
// 	if r.Name != "name" {
// 		t.Fatalf("name is %q, want %q", r.Name, "name")
// 	}
// 	if err := r.Close(); err != nil {
// 		t.Fatalf("Reader.Close: %v", err)
// 	}
// }

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
