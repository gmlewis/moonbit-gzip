/// `IOReadCloser` is similar to Go's `io.ReadCloser`.
pub trait IOReadCloser {
  read(Self, ArrayView[Byte]) -> Int!Error
  close(Self) -> Unit!Error
}

// let io_read_closer_buf_size = 1024

// pub fn to_bytes(self : IOReadCloser) -> Bytes!Error {
//   let buf = @buffer.new()
//   let b = Array::make(io_read_closer_buf_size, b'\x00')
//   for {
//     let n = try {
//       self.read!(b[:])
//     } catch {
//       IOEOF => 0
//       e => raise e
//     }
//     if n == 0 {
//       self.close!()
//       break
//     }
//     for i = 0; i < n; i = i + 1 {
//       buf.write_byte(b[i])
//     }
//   }
//   buf.to_bytes()
// }
