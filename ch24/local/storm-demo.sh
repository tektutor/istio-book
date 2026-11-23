#!/usr/bin/env bash
# Builds a retry storm with Envoy alone, then stops it. Two Envoys play
# the sidecars: one in front of orders (the curl pod's sidecar) and one
# in front of inventory (the orders pod's sidecar). Last, fortio sends
# 200 failing requests with and without a retry budget.
# You need Envoy and fortio on your PATH, and a Python environment with
# the packages in shop/orders/requirements.txt.
#
# Usage: ch24/local/storm-demo.sh       (from the repository root)
set -uo pipefail

INV_LOG=/tmp/ch24-inventory.log
ORD_LOG=/tmp/ch24-orders.log
INV="outbound|8080||inventory.shop.svc.cluster.local"
ORD="outbound|8080||orders.shop.svc.cluster.local"
RETRY_ON="connect-failure,refused-stream,unavailable,cancelled,reset,503"
PIDS=()
cleanup() { kill "${PIDS[@]}" 2>/dev/null; }
trap cleanup EXIT

PORT=18080 POD_NAME=inventory-1 python3 shop/inventory/app.py \
  > $INV_LOG 2>&1 & PIDS+=($!)

start_envoy() {                   # start_envoy NAME BASE_ID ADMIN [options]
  local name=$1 id=$2 admin=$3; shift 3
  python3 ch24/local/sidecar_route.py --admin "$admin" \
    --log /tmp/ch24-$name-access.log "$@" > /tmp/ch24-$name.json
  envoy -c /tmp/ch24-$name.json --base-id "$id" --log-level error \
    > /tmp/ch24-$name.log 2>&1 & PIDS+=($!)
  until curl -s http://127.0.0.1:$admin/ready 2>/dev/null | grep -q LIVE
  do sleep 0.2; done
}
stop_envoys() { pkill -f 'ch24-(edge|mesh|load).json'; sleep 1; }
count() { grep -c ' SKU-7 ' $INV_LOG; }

run() {                           # run APP_RETRIES EDGE_OPTIONS...
  local app_retries=$1; shift
  stop_envoys
  pkill -f 'shop/orders/app.py'; sleep 1
  start_envoy mesh 50 9902 --listen 10000 --upstream 18080 \
    --cluster "$INV" --timeout 10s --attempts 3 --per-try 2s \
    --retry-on "$RETRY_ON"                                      # (1)
  start_envoy edge 51 9903 --listen 10001 --upstream 18081 \
    --cluster "$ORD" "$@"                                       # (2)
  PORT=18081 POD_NAME=orders-1 APP_RETRIES=$app_retries \
    INVENTORY_URL=http://127.0.0.1:10000 python3 shop/orders/app.py \
    > $ORD_LOG 2>&1 & PIDS+=($!)
  sleep 2
  local before; before=$(count)
  curl -s -w "\n%{http_code} %{time_total}s\n" \
    http://127.0.0.1:10001/api/orders/7
  sleep 2
  echo "inventory requests: $(( $(count) - before ))"
}

sleep 2
curl -s -X POST "http://127.0.0.1:18080/admin/faults?fail=100" > /dev/null
echo "### Retries in three layers: edge route, orders code, mesh route"
run 2 --timeout 60s --attempts 3 --per-try 15s --retry-on 5xx    # (3)
echo "### One retry layer: no edge retries, no code retries"
run 0 --timeout 12s --attempts 0

budget_run() {                    # budget_run [--budget PERCENT]
  stop_envoys
  start_envoy load 52 9904 --listen 10002 --upstream 18080 \
    --cluster "$INV" --timeout 10s --attempts 3 --per-try 2s \
    --retry-on "$RETRY_ON" "$@"
  fortio load -quiet -c 50 -n 200 -qps 0 \
    http://127.0.0.1:10002/api/stock/SKU-1 2>&1 | grep -E '^Code|All done'
  curl -s http://127.0.0.1:9904/stats | grep -F "cluster.$INV." |
    sed 's/^.*local\.//' |
    grep -E '^upstream_rq_(total|retry|retry_overflow):'
}
curl -s -X POST "http://127.0.0.1:18080/admin/faults?fail=100&delay=200ms" \
  > /dev/null
echo "### 200 failing requests, 50 at a time, no retry budget"
budget_run
echo "### The same with a retry budget of 20 percent"
budget_run --budget 20                                          # (4)
