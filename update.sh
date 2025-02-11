#!/bin/bash -ex
moon update && moon install && rm -rf target
moon add moonbitlang/x
moon fmt && moon info
moon test --target native
moon test --target all
