#!/usr/bin/env bash
# Sends ten completion requests through the inference gateway and counts
# which model server pod answered each one.
#
# Usage: ch15/inference/ask-model.sh <gateway address>
set -euo pipefail
GW=${1:?gateway address}

for i in $(seq 1 10); do
  curl -s -D - -o /dev/null "http://$GW/v1/completions" \
    -H 'Content-Type: application/json' \
    -d '{"model": "Qwen/Qwen3-0.6B", "prompt": "Name a book",
         "max_tokens": 20}' |
    tr -d '\r' | grep -i '^x-inference-pod:' || echo "no pod header"
done | sort | uniq -c
