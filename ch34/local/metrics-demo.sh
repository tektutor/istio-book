#!/usr/bin/env bash
# Runs orders and inventory from the shop with two sidecars that carry
# Istio's metrics filters, sends load with Fortio in three phases, and
# asks Prometheus the questions of Chapter 34.
# You need the contrib build of Envoy as envoy-contrib, Fortio,
# Prometheus and promtool, openssl, and python3 with the packages of
# the shop services and cryptography.
#
# Usage: ch34/local/metrics-demo.sh       (from the repository root)
set -uo pipefail

CERTS=/tmp/ch34-certs
CA=$(mktemp -d)
DATA=$(mktemp -d)
rm -rf $CERTS; mkdir -p $CERTS
ch28/ca/make-root.sh "$CA" > /dev/null
ch28/ca/make-intermediate.sh lab "$CA" > /dev/null
for sa in orders inventory; do
  python3 ch28/ca/issue_workload_cert.py "$CA/lab" shop $sa 24 \
    tektutor.org > /dev/null
  cp -r "$CA/lab/shop-$sa" $CERTS/$sa
done
cp "$CA/lab/root-cert.pem" $CERTS/

PIDS=()
start() { "$@" > "$DATA/$(basename "$1").$RANDOM.log" 2>&1 & PIDS+=($!); }
trap 'kill "${PIDS[@]}" 2>/dev/null; wait 2>/dev/null; rm -rf "$CA" "$DATA"' EXIT
PORT=18981 POD_NAME=inventory-5b8c7-q9w4z start python3 shop/inventory/app.py
PORT=18980 POD_NAME=orders-6d4f9-x7k2p INVENTORY_URL=http://127.0.0.1:18970 \
  start python3 shop/orders/app.py
start envoy-contrib -c ch34/local/orders-sidecar.yaml --base-id 70 \
  --log-level error
start envoy-contrib -c ch34/local/inventory-sidecar.yaml --base-id 71 \
  --log-level error
start prometheus --config.file=ch34/local/prometheus.yaml \
  --storage.tsdb.path="$DATA/tsdb" --web.listen-address=127.0.0.1:19090
until curl -sf -o /dev/null http://127.0.0.1:18980/api/orders/1 &&
      curl -sf -o /dev/null http://127.0.0.1:19090/-/ready; do sleep 0.5; done

faults() { curl -s -X POST "http://127.0.0.1:18981/admin/faults?$1"; }
load() {                                                         # (1)
  echo "### Phase $1: $2"
  fortio load -quiet -allow-initial-errors -qps 20 -c 4 -t 30s \
    http://127.0.0.1:18980/api/orders/7 2>&1 | grep -E "^Code|^# target 99%"
  date +%s > "$DATA/phase$1"
}
load 1 "healthy"
faults "fail=20" > /dev/null
load 2 "inventory fails 20% of the requests with 503"
faults "fail=0&delay=250ms" > /dev/null
load 3 "inventory answers after 250 ms"
sleep 4                                       # one more scrape and rule run

echo "### One series from the inventory sidecar"                 # (2)
curl -s http://127.0.0.1:19971/stats/prometheus |
  grep '^istio_requests_total{.*response_code="503"' | head -1 |
  sed 's/{/{\n  /; s/",/",\n  /g; s/} /\n} /'

q() {                                     # q <unix time> <PromQL query>
  curl -s http://127.0.0.1:19090/api/v1/query --data-urlencode "time=$1" \
    --data-urlencode "query=$2" | python3 -c '
import json, sys
for r in json.load(sys.stdin)["data"]["result"]:
    m = r["metric"]
    name, value = m.pop("__name__", ""), float(r["value"][1])
    labels = ", ".join(f"{k}=\"{v}\"" for k, v in sorted(m.items()))
    print(f"{value:10.4g}  {name}" + (f"{{{labels}}}" if labels else ""))'
}
for p in 1 2 3; do
  t=$(cat "$DATA/phase$p")
  echo "### Phase $p: requests per second by reporter and response code"
  q "$t" 'sum by (reporter, response_code) (rate(
           istio_requests_total{destination_service_name="inventory"}[25s]))'
  echo "### Phase $p: error ratio and p99 latency (ms) seen by orders"
  q "$t" '(sum(rate(istio_requests_total{reporter="source",
             destination_service_name="inventory",response_code=~"5.."}[25s]))
           or vector(0))                                         # (3)
          / sum(rate(istio_requests_total{reporter="source",
             destination_service_name="inventory"}[25s]))'
  q "$t" 'histogram_quantile(0.99, sum by (le) (rate(
             istio_request_duration_milliseconds_bucket{reporter="source",
             destination_service_name="inventory"}[25s])))'
done
echo "### The recording rules and alerts of Lab 34.1, at the end"   # (4)
q "$(date +%s)" 'sum by (__name__) (
                   {__name__=~"service:istio_request_error_ratio:.*"})'
q "$(date +%s)" 'count by (alertname) (ALERTS{alertstate="firing"})'
echo "### Encryption, seen by inventory"
q "$(date +%s)" 'sum by (connection_security_policy, source_principal) (
                   istio_requests_total{reporter="destination"})'
echo "### The bucket bounds, as Prometheus stored them"
curl -s http://127.0.0.1:19090/api/v1/label/le/values; echo
echo "### Series per metric name"                                # (5)
q "$(date +%s)" 'count by (__name__) ({__name__=~"istio_.*"})'
