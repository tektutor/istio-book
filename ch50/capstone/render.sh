#!/usr/bin/env bash
# Renders both overlays into plain files, so that the static checks of
# Chapter 48 see whole resources, not kustomize patches.
#
# Usage: ch50/capstone/render.sh OUTPUT_DIR
#        then: ci/check.sh OUTPUT_DIR/sidecar OUTPUT_DIR/ambient
set -euo pipefail
out=${1:?usage: render.sh OUTPUT_DIR}
here=$(dirname "$0")
for mode in sidecar ambient; do
  mkdir -p "$out/$mode"
  file="$out/$mode/all.yaml"
  kubectl kustomize "$here/$mode" > "$file"
  echo "$file: $(grep -c '^kind:' "$file") resources"
done
