#!/usr/bin/env bash
# Builds tenant_check.wasm with Go 1.24 or later, as a WASI reactor.
set -euo pipefail
cd "$(dirname "$0")"
GOOS=wasip1 GOARCH=wasm go build -buildmode=c-shared \
  -o tenant_check.wasm .                        # (1)
ls -l tenant_check.wasm
