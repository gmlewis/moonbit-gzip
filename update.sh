#!/bin/bash -ex
moon update && rm -rf _build .mooncakes
moon add --upgrade moonbitlang/x
moon fmt && moon info
moon test -j 12 --target all
