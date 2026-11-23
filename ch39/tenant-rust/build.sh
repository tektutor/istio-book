#!/usr/bin/env bash
# Builds tenant_check.wasm. With the wasm32 target from rustup, run
#   rustup target add wasm32-unknown-unknown
#   cargo build --release --target wasm32-unknown-unknown
# This script does the same with a toolchain that has no prebuilt
# standard library for wasm32: it builds the library from source.
set -euo pipefail
cd "$(dirname "$0")"
if rustup target list --installed 2>/dev/null | grep -q wasm32-unknown; then
  cargo build --release --target wasm32-unknown-unknown
else
  RUSTC_BOOTSTRAP=1 cargo build --release --target wasm32-unknown-unknown \
    -Zbuild-std=std,panic_abort                 # (1)
fi
ls -l target/wasm32-unknown-unknown/release/tenant_check.wasm
