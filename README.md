# gmlewis/gzip
[![check](https://github.com/gmlewis/moonbit-gzip/actions/workflows/check.yml/badge.svg)](https://github.com/gmlewis/moonbit-gzip/actions/workflows/check.yml)

This is a simplified gzip/gunzip algorithm based on Go's implementation:
https://cs.opensource.google/go/go/+/refs/tags/go1.23.0:src/compress/gzip/gzip.go
which has the copyright notice:

```
// Copyright 2010 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.
```

## Status

The code has been updated to support compiler:

```bash
$ moon version --all
moon 0.1.20250310 (df3bb14 2025-03-10) ~/.moon/bin/moon
moonc v0.1.20250310+a7a1e9804 ~/.moon/bin/moonc
moonrun 0.1.20250310 (df3bb14 2025-03-10) ~/.moon/bin/moonrun
```

Use `moonup` to manage `moon` compiler versions:
https://github.com/chawyehsu/moonup
