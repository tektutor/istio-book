#!/usr/bin/env bash
# Sends requests through the sidecars of orders and inventory with
# tracing to Jaeger: one request, one request through an application
# that drops the trace headers, and 200 requests at 10% sampling.
# You need the contrib build of Envoy as envoy-contrib, Jaeger 2, and
# python3 with the packages of the shop services.
#
# Usage: ch35/local/tracing-demo.sh       (from the repository root)
set -uo pipefail

LOGS=$(mktemp -d)
PIDS=()
start() { "$@" > "$LOGS/$(basename "$1").$RANDOM.log" 2>&1 & PIDS+=($!); }
trap 'kill "${PIDS[@]}" 2>/dev/null; wait 2>/dev/null; rm -rf "$LOGS"' EXIT
start jaeger                                  # all in one, spans in memory
PORT=18983 POD_NAME=inventory-5b8c7-q9w4z start python3 shop/inventory/app.py
orders() {                                    # orders, calling inventory at $1
  PORT=18982 POD_NAME=orders-6d4f9-x7k2p INVENTORY_URL=$1 \
    python3 shop/orders/app.py > "$LOGS/orders.log" 2>&1 &
  ORDERS=$!
  until curl -sf -o /dev/null http://127.0.0.1:18982/healthz; do sleep 0.2; done
}
start envoy-contrib -c ch35/local/tracing-envoy.yaml --base-id 77 \
  --log-level error
until curl -sf -o /dev/null http://127.0.0.1:16686/ &&
      curl -s http://127.0.0.1:19990/ready | grep -q LIVE; do sleep 0.5; done

API='http://127.0.0.1:16686/api/traces?service=orders.shop&limit=1000'
since() { echo "&start=$1&end=$(( $(date +%s%N) / 1000 ))"; }   # (1)
traces() { sleep 7; curl -s "$API$(since "$1")"; }               # (2)

echo "### 1. One request; orders copies the trace headers"
orders http://127.0.0.1:18991
T=$(( $(date +%s%N) / 1000 ))
curl -s -o /dev/null -w "HTTP %{http_code}\n" http://127.0.0.1:18990/api/orders/7
traces $T | python3 ch35/local/show_traces.py http.status_code \
  istio.canonical_service guid:x-request-id

echo "### 2. One request; the application drops the trace headers"
kill $ORDERS; wait $ORDERS 2>/dev/null
orders http://127.0.0.1:18993                                    # (3)
T=$(( $(date +%s%N) / 1000 ))
curl -s -o /dev/null http://127.0.0.1:18990/api/orders/7
traces $T | python3 ch35/local/show_traces.py
kill $ORDERS; wait $ORDERS 2>/dev/null

echo "### 3. 200 requests at 10% sampling"
kill "${PIDS[-1]}"; wait "${PIDS[-1]}" 2>/dev/null               # (4)
python3 - > "$LOGS/sampling.yaml" <<'PY'
import yaml
cfg = yaml.safe_load(open("ch35/local/tracing-envoy.yaml"))
for listener in cfg["static_resources"]["listeners"]:
    hcm = listener["filter_chains"][0]["filters"][0]["typed_config"]
    if "tracing" in hcm:
        hcm["tracing"]["random_sampling"] = {"value": 10}
print(yaml.safe_dump(cfg))
PY
start envoy-contrib -c "$LOGS/sampling.yaml" --base-id 77 --log-level error
until curl -s http://127.0.0.1:19990/ready | grep -q LIVE; do sleep 0.2; done
orders http://127.0.0.1:18991
T=$(( $(date +%s%N) / 1000 ))
for i in $(seq 1 200); do
  curl -s -o /dev/null http://127.0.0.1:18990/api/orders/$i
done
traces $T | python3 -c '
import json, sys
data = json.load(sys.stdin)["data"]
full = [t for t in data if len(t["spans"]) == 3]
print(f"{len(data)} traces kept, {len(full)} of them with all 3 spans")'
kill $ORDERS
