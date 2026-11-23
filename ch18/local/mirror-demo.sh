#!/usr/bin/env bash
# Shows, without a cluster, what mirroring does: users get v1's answers,
# while v2 gets a copy of every request. v2 fails one request in five
# and is slow, and the users do not notice.
# You need python3 with fastapi and uvicorn, and Envoy on your PATH.
#
# Usage: ch18/local/mirror-demo.sh       (from the repository root)
set -uo pipefail

PIDS=()
cleanup() { kill "${PIDS[@]}" 2>/dev/null; }
trap cleanup EXIT

PORT=18091 POD_NAME=inventory-v1 python3 shop/inventory/app.py \
  > /tmp/inv-v1.log 2>&1 & PIDS+=($!)
PORT=18092 POD_NAME=inventory-v2 python3 shop/inventory/app.py \
  > /tmp/inv-v2.log 2>&1 & PIDS+=($!)
envoy -c ch18/local/mirror-envoy.yaml --base-id 44 --log-level error \
  > /tmp/envoy-mirror.log 2>&1 & PIDS+=($!)
sleep 3

echo "### v2 gets worse: 20 percent errors and 500 ms delay"   # (1)
curl -s -X POST "127.0.0.1:18092/admin/faults?fail=20&delay=500ms"

echo "### 100 requests from users: status codes and the slowest"  # (2)
for i in $(seq 1 100); do
  curl -s -o /dev/null -w "%{http_code} %{time_total}\n" \
    127.0.0.1:18300/api/stock/SKU-1
done > /tmp/answers.txt
cut -d' ' -f1 /tmp/answers.txt | sort | uniq -c
sort -k2 -n /tmp/answers.txt | tail -1 | sed 's/^/slowest: /'

sleep 1                                  # let the last copies finish
echo "### What each version answered, from Envoy's statistics"   # (3)
curl -s 127.0.0.1:19904/stats |
  grep -E "^cluster\.inventory_v[12]\.upstream_rq_[0-9]{3}:" | sort
