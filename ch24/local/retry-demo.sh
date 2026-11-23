#!/usr/bin/env bash
# Runs the inventory service behind one Envoy that plays the client's
# sidecar, and tries six route settings in turn: Istio's default, a
# timeout, retries on 503, retries on slow answers, retries without the
# reset condition, and retries when half of all requests fail.
# You need Envoy and fortio on your PATH, and a Python environment with
# the packages in shop/inventory/requirements.txt.
#
# Usage: ch24/local/retry-demo.sh       (from the repository root)
set -uo pipefail

LOG=/tmp/ch24-inventory.log
CLUSTER="outbound|8080||inventory.shop.svc.cluster.local"
RETRY_ON="connect-failure,refused-stream,unavailable,cancelled,reset,503"
URL=http://127.0.0.1:10000/api/stock/SKU-7
PIDS=()
ENVOY=
cleanup() { kill "${PIDS[@]}" $ENVOY 2>/dev/null; }
trap cleanup EXIT

PORT=18080 POD_NAME=inventory-1 python3 shop/inventory/app.py \
  > $LOG 2>&1 & PIDS+=($!)
sleep 2

sidecar() {                       # sidecar [options for sidecar_route.py]
  [ -n "$ENVOY" ] && kill $ENVOY && wait $ENVOY 2>/dev/null
  rm -f /tmp/ch24-access.log
  python3 ch24/local/sidecar_route.py "$@" > /tmp/ch24-envoy.json
  envoy -c /tmp/ch24-envoy.json --base-id 49 --log-level error \
    --file-flush-interval-msec 200 > /tmp/ch24-envoy.log 2>&1 &
  ENVOY=$!
  until curl -s http://127.0.0.1:9901/ready 2>/dev/null | grep -q LIVE; do
    sleep 0.2
  done
}
faults() { curl -s -X POST "http://127.0.0.1:18080/admin/faults?$1"; echo; }
call() { curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" $URL; }
inventory_log() { sleep "$2"; grep ' SKU-7 ' $LOG | tail -n "$1"; }   # (1)
stats() {                         # stats NAMES: counters of the cluster
  curl -s http://127.0.0.1:9901/stats | grep -F "cluster.$CLUSTER." |
    sed 's/^.*local\.//' | grep -E "^upstream_rq_($1):"          # (2)
}

echo "### 1. No retries block: Istio's default policy, every answer 503"
sidecar
faults "fail=100"
call
inventory_log 1 0.5

echo "### 2. timeout: 2s and attempts: 0, every answer 3 s late"
sidecar --timeout 2s --attempts 0
faults "delay=3s"
curl -s -w "\n%{http_code} %{time_total}s\n" $URL
sleep 1
cat /tmp/ch24-access.log

echo "### 3. Three retries, 2 s per try, every answer 503"
sidecar --timeout 10s --attempts 3 --per-try 2s --retry-on "$RETRY_ON"
faults "fail=100"
call
inventory_log 4 0.5
stats "retry|retry_limit_exceeded"

echo "### 4. The same route, every answer 3 s late"
sidecar --timeout 10s --attempts 3 --per-try 2s --retry-on "$RETRY_ON"
faults "delay=3s"
call
inventory_log 4 1.5
stats "retry|per_try_timeout"

echo "### 5. The same route without reset in retryOn"               # (3)
sidecar --timeout 10s --attempts 3 --per-try 2s \
  --retry-on "connect-failure,refused-stream,unavailable,cancelled,503"
faults "delay=3s"
call
inventory_log 1 1.5
stats "retry|per_try_timeout"

echo "### 6. Three retries, half of all answers 503, 100 requests"
sidecar --timeout 10s --attempts 3 --per-try 2s --retry-on "$RETRY_ON"
faults "fail=50"
fortio load -quiet -c 1 -n 100 -qps 0 $URL 2>&1 | grep '^Code'      # (4)
stats "total|retry"
