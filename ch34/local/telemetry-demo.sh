#!/usr/bin/env bash
# Sends the same 200 requests from the orders sidecar to the inventory
# sidecar three times: with the default metrics, with a path label, and
# with the shop's settings. Counts the series that inventory reports.
# You need what metrics-demo.sh needs, and python3 with PyYAML.
#
# Usage: ch34/local/telemetry-demo.sh       (from the repository root)
set -uo pipefail

CERTS=/tmp/ch34-certs
CA=$(mktemp -d)
WORK=$(mktemp -d)
rm -rf $CERTS; mkdir -p $CERTS
ch28/ca/make-root.sh "$CA" > /dev/null
ch28/ca/make-intermediate.sh lab "$CA" > /dev/null
for sa in orders inventory; do
  python3 ch28/ca/issue_workload_cert.py "$CA/lab" shop $sa 24 \
    tektutor.org > /dev/null
  cp -r "$CA/lab/shop-$sa" $CERTS/$sa
done
cp "$CA/lab/root-cert.pem" $CERTS/
PORT=18981 python3 shop/inventory/app.py > "$WORK/app.log" 2>&1 &
APP=$!
envoy-contrib -c ch34/local/orders-sidecar.yaml --base-id 70 \
  --log-level error > "$WORK/orders.log" 2>&1 &
ORDERS=$!
until curl -sf -o /dev/null http://127.0.0.1:18981/healthz; do sleep 0.2; done
INV=
trap 'kill $APP $ORDERS $INV 2>/dev/null; rm -rf "$CA" "$WORK"' EXIT

variant() {                      # writes the inventory config for $1
  python3 - "$1" > "$WORK/inventory.yaml" <<'PY'
import sys, yaml
cfg = yaml.safe_load(open("ch34/local/inventory-sidecar.yaml"))
if sys.argv[1] != "default":
    extra = yaml.safe_load(open("ch34/local/stats-overrides.yaml"))
    hcm = cfg["static_resources"]["listeners"][0]["filter_chains"][0]
    filters = hcm["filters"][0]["typed_config"]["http_filters"]
    stats = next(f for f in filters if f["name"] == "istio.stats")
    stats["typed_config"].update(extra[sys.argv[1]])           # (1)
print(yaml.safe_dump(cfg))
PY
}
for v in default path_label shop_metrics; do
  variant $v
  envoy-contrib -c "$WORK/inventory.yaml" --base-id 71 \
    --log-level error > "$WORK/inventory.log" 2>&1 &
  INV=$!
  until curl -sf -o /dev/null http://127.0.0.1:18970/healthz; do
    sleep 0.2; done
  for i in $(seq 1 100); do                                     # (2)
    curl -s -o /dev/null http://127.0.0.1:18970/api/stock/SKU-$i
    curl -s -o /dev/null http://127.0.0.1:18970/healthz
  done
  curl -s http://127.0.0.1:19971/stats/prometheus |
    grep '^istio_' | grep -v '^istio_build' > "$WORK/$v.txt"
  echo "### $v: $(wc -l < "$WORK/$v.txt") series in inventory's metrics"
  sed 's/{.*//' "$WORK/$v.txt" | sort | uniq -c                 # (3)
  grep -o 'response_code="200".*\(api\|request_path\)="[^"]*"' \
    "$WORK/$v.txt" | grep -o '\(api\|request_path\)="[^"]*"' | head -3
  kill $INV; wait $INV 2>/dev/null
done
