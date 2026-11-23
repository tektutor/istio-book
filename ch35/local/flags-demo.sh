#!/usr/bin/env bash
# Produces ten response flags with one request each through an Envoy
# with Istio's access log format, prints the log, and then asks Loki for
# the error lines that the OpenTelemetry access logger shipped there.
# You need the contrib build of Envoy as envoy-contrib, the OpenTelemetry
# Collector contrib build as otelcol-contrib, Loki, logcli and python3.
#
# Usage: ch35/local/flags-demo.sh       (from the repository root)
set -uo pipefail

rm -rf /tmp/ch35-loki /tmp/ch35-access.log
LOGS=$(mktemp -d)
PIDS=()
start() { "$@" > "$LOGS/$(basename "$1").$RANDOM.log" 2>&1 & PIDS+=($!); }
trap 'kill "${PIDS[@]}" 2>/dev/null; wait 2>/dev/null; rm -rf "$LOGS"' EXIT
start loki -config.file=ch35/local/loki.yaml
start otelcol-contrib --config=ch35/local/otelcol.yaml
start python3 ch35/local/upstream.py 18986
start envoy-contrib -c ch35/local/flags-envoy.yaml --base-id 75 \
  --log-level error --file-flush-interval-msec 100
until curl -s http://127.0.0.1:19995/ready | grep -q LIVE &&
      curl -sf -o /dev/null http://127.0.0.1:13100/ready; do sleep 0.5; done

U=http://127.0.0.1:18995
req() {                                  # req [curl options] URL
  local url=${*: -1} code
  code=$(curl -s -o /dev/null -w "%{http_code}" "$@")
  printf "%-11s %s\n" "${url#"$U"}" "$code"
}
echo "### One request per flag"
req $U/uf/1;  req $U/urx/1;  req $U/uh/1;  req $U/uc/1
req $U/ut/1;  req $U/nothing/1                                    # (1)
UO=(); for i in 1 2 3; do req $U/uo/$i & UO+=($!); done
wait "${UO[@]}"                                                   # (2)
req $U/rl/1;  req $U/rl/2                                         # (3)
req $U/uaex/1
req --max-time 0.5 $U/dc/1                                        # (4)
sleep 3                                       # the slow calls finish
echo "### The full log line of the UF request"
grep ' "GET /uf/1 ' /tmp/ch35-access.log
echo "### Path, code, flags and details of every request"
awk '{print $3, $5, $6, $7}' /tmp/ch35-access.log | sort         # (5)
sleep 5                                       # the collector's batch
echo "### Loki: error lines of the workload orders, by flag"
logcli --addr=http://127.0.0.1:13100 --quiet instant-query \
  'sum by (response_flags) (count_over_time(
     {service_name="orders"} [5m]))' |
  python3 -c '
import json, sys
rows = json.load(sys.stdin)
for r in sorted(rows, key=lambda r: r["metric"]["response_flags"]):
    flags, count = r["metric"]["response_flags"], r["value"][1]
    print(f"{flags:8} {count}")'
echo "### Loki: the lines with an upstream failure"
logcli --addr=http://127.0.0.1:13100 --quiet query --output=raw \
  --since=5m '{service_name="orders"} | response_flags=~".*U[FH].*"'
