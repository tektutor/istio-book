#!/usr/bin/env bash
# Shows, without a cluster, how consistent hashing keeps one user on one
# pod. Two inventory instances stand for two pods; one Envoy has a
# LEAST_REQUEST cluster and a RING_HASH cluster in front of them.
# You need python3 with fastapi and uvicorn, and Envoy on your PATH.
#
# Usage: ch17/local/lb-demo.sh       (from the repository root)
set -uo pipefail

PIDS=()
cleanup() { kill "${PIDS[@]}" 2>/dev/null; }
trap cleanup EXIT

PORT=18081 POD_NAME=inventory-pod-a python3 shop/inventory/app.py \
  > /tmp/inv-a.log 2>&1 & PIDS+=($!)
PORT=18082 POD_NAME=inventory-pod-b python3 shop/inventory/app.py \
  > /tmp/inv-b.log 2>&1 & PIDS+=($!)
envoy -c ch17/local/lb-envoy.yaml --base-id 43 --log-level error \
  > /tmp/envoy-lb.log 2>&1 & PIDS+=($!)
sleep 3

ask() {                     # ask PORT USER: ten requests, count the pods
  for i in $(seq 1 10); do
    curl -s -H "x-shop-user: $2" "127.0.0.1:$1/api/stock/SKU-1" |
      grep -o '"pod":"[^"]*"'
  done | sort | uniq -c
}

echo "### LEAST_REQUEST, user kayal";    ask 18100 kayal
echo "### RING_HASH, user kayal";        ask 18200 kayal
echo "### RING_HASH, user prabhu";        ask 18200 prabhu
echo "### RING_HASH, user james";       ask 18200 james
echo "### RING_HASH, no header";        ask 18200 ""
