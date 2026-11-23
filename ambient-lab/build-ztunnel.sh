#!/usr/bin/env bash
# Builds ztunnel 1.31 and the lab's node agent from source. You need git,
# a Rust toolchain (rustup.rs), protoc, cmake and clang.
#
# Usage: ambient-lab/build-ztunnel.sh [install dir]   (default /usr/local/bin)
set -euo pipefail
DIR=$(cd "$(dirname "$0")" && pwd)
OUT=${1:-/usr/local/bin}
SRC=${ZTUNNEL_SRC:-/tmp/ambient-lab/ztunnel-src}

[[ -d $SRC/src ]] || git clone --depth 1 -b release-1.31 \
  https://github.com/istio/ztunnel.git "$SRC"
cp "$DIR/nodeagent.rs" "$SRC/examples/nodeagent.rs"           # (1)
cd "$SRC"
cargo build --release --features testing                        # (2)
cargo build --release --features testing --example nodeagent
install -m 0755 out/rust/release/ztunnel \
  out/rust/release/examples/nodeagent "$OUT/"
"$OUT/ztunnel" version 2>/dev/null | head -1 || true
