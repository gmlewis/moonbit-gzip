type! IOErrUnexpectedEOF  derive(Show)

/// `IOReader` is similar to Go's `io.Reader` interface.
pub trait IOReader {
  read_byte(Self) -> Byte!Error
  read_full(Self, ArrayView[Byte]) -> Int!Error
}

// pub fn IOReader::from_buffer(buf : @buffer.Buffer) -> BufferIOReader {
//   { bytes: buf.to_bytes(), offset: 0 }
// }

// struct BufferIOReader {
//   bytes : Bytes
//   mut offset : Int
// }

// fn read_byte(self : BufferIOReader) -> Byte!Error {
//   let remaining = self.bytes.length() - self.offset
//   if remaining <= 0 {
//     raise IOEOF
//   }
//   let b = self.bytes[self.offset]
//   self.offset += 1
//   b
// }

// fn read_full(self : BufferIOReader, b : ArrayView[Byte]) -> Int!Error {
//   let remaining = self.bytes.length() - self.offset
//   let n = b.length()
//   if remaining < n {
//     raise IOEOF
//   }
//   for i = 0; i < n; i = i + 1 {
//     b[i] = self.bytes[self.offset + i]
//   }
//   self.offset += n
//   n
// }
