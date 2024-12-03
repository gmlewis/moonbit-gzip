#!/bin/bash -ex
moon update && moon install && rm -rf target
moon fmt
moon test --target native
# moon test --target all
# 2024-12-03 - wasm target is now failing
moon test --target wasm-gc
moon test --target js
