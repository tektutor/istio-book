#!/usr/bin/env bash
# Packages a .wasm file as an OCI image with one layer that holds
# plugin.wasm, the format Istio reads, and pushes it with crane.
#
# Usage: push-plugin.sh MODULE.wasm IMAGE     for example
#   push-plugin.sh ch39/tenant-rust/target/wasm32-unknown-unknown/release/\
#   tenant_check.wasm localhost:5000/tenant-check:1.0.0
set -euo pipefail
module=$1 image=$2
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
cp "$module" "$work/plugin.wasm"                             # (1)
tar -C "$work" -cf "$work/layer.tar" plugin.wasm
crane append --oci-empty-base -f "$work/layer.tar" -t "$image" \
  ${INSECURE:+--insecure}                                    # (2)
crane digest ${INSECURE:+--insecure} "$image"                # (3)
