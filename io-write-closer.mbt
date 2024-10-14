/// `IOWriteCloser` is similar to Go's `io.WriteCloser` interface.
pub trait IOWriteCloser {
  write(Self, ArrayView[Byte]) -> Int!Error
  close(Self) -> Unit!Error
}
