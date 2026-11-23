#!/usr/bin/env bash
# Runs the inventory service behind one Envoy with fault injection rules
# and sends requests with and without the test header. Last, it shows
# how an injected delay and a route timeout interact.
# You need Envoy and fortio on your PATH, and a Python environment with
# the packages in shop/inventory/requirements.txt.
#
# Usage: ch26/local/fault-demo.sh       (from the repository root)
set -uo pipefail

LOG=/tmp/ch26-inventory.log
PIDS=()
cleanup() { kill "${PIDS[@]}" 2>/dev/null; }
trap cleanup EXIT
PORT=18080 POD_NAME=inventory-1 python3 shop/inventory/app.py \
  > $LOG 2>&1 & PIDS+=($!)
rm -f /tmp/ch26-access.log
envoy -c ch26/local/fault-envoy.yaml --base-id 54 --log-level error \
  --file-flush-interval-msec 200 > /tmp/ch26-envoy.log 2>&1 & PIDS+=($!)
until curl -s http://127.0.0.1:19926/ready 2>/dev/null | grep -q LIVE
do sleep 0.2; done
sleep 1

call() {                          # call PORT [HEADER VALUE]
  local h=()
  [ -n "${2:-}" ] && h=(-H "x-test-fault: $2")
  curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" "${h[@]}" \
    http://127.0.0.1:$1/api/stock/SKU-1
}
requests() { grep -c ' SKU-1 ' $LOG; }                          # (1)

echo "### 1. No test header"
call 18310
echo "### 2. x-test-fault: delay"
call 18310 delay
echo "### 3. x-test-fault: abort"
before=$(requests); call 18310 abort
echo "requests that reached inventory: $(( $(requests) - before ))"
echo "### 4. x-test-fault: half, 40 requests"
fortio load -quiet -c 1 -qps 0 -n 40 -H "x-test-fault: half" \
  http://127.0.0.1:18310/api/stock/SKU-1 2>&1 | grep '^Code'
echo "### 5. x-test-fault: forgot, an abort without a percentage"
call 18310 forgot
echo "### 6. Route timeout 1s and an injected delay of 3s"
call 18311 delay
echo "### 7. Route timeout 1s and a service that answers after 3s"
curl -s -X POST "http://127.0.0.1:18080/admin/faults?delay=3s" > /dev/null
call 18311
sleep 1
echo "### The access log, counted by status, flag and detail"
sed 's/ [0-9]*ms / /' /tmp/ch26-access.log | sort | uniq -c   # (2)
