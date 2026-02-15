#!/bin/bash -ex
moon update && rm -rf _build .mooncakes
moon add moonbitlang/x
moon fmt && moon info
moon test -j 12 --target all
