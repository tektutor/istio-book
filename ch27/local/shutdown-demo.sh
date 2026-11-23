#!/usr/bin/env bash
# Shows what happens when the inventory service gets SIGTERM behind its
# sidecar: the request in flight finishes, but a new request that the
# sidecar still accepts finds no application, and the caller gets 503.
# You need Envoy, bc, python3 and the packages in
# shop/inventory/requirements.txt.
#
# Usage: ch27/local/shutdown-demo.sh       (from the repository root)
set -uo pipefail

rm -f /tmp/ch27-access.log
envoy -c ch27/local/uc-envoy.yaml --base-id 55 --log-level error \
  --file-flush-interval-msec 200 > /tmp/ch27-envoy.log 2>&1 &
ENVOY=$!
trap 'kill $ENVOY 2>/dev/null' EXIT
PORT=18401 POD_NAME=inventory-1 python3 shop/inventory/app.py \
  > /tmp/ch27-inventory.log 2>&1 &
APP=$!
until curl -s http://127.0.0.1:19927/ready 2>/dev/null | grep -q LIVE &&
      curl -s http://127.0.0.1:18401/healthz > /dev/null
do kill -0 $ENVOY $APP || exit 1; sleep 0.2; done
curl -s -X POST "http://127.0.0.1:18401/admin/faults?delay=2s" > /dev/null

URL=http://127.0.0.1:18400/api/stock/SKU-1          # through the sidecar
START=$(date +%s.%N)
stamp() { printf "%4.1fs " "$(echo "$(date +%s.%N) - $START" | bc)"; }

( code=$(curl -s -o /dev/null -w "%{http_code}" $URL)
  stamp; echo "request A, sent at 0.0s, answered $code" ) &       # (1)
sleep 0.5
stamp; echo "SIGTERM to the application"
kill -TERM $APP                                                # (2)
sleep 0.5
code=$(curl -s -o /dev/null -w "%{http_code}" $URL)
stamp; echo "request B, sent at 1.0s, answered $code"          # (3)
wait $APP
stamp; echo "application exited"
sleep 0.5
echo "### The sidecar's access log"
cat /tmp/ch27-access.log                                       # (4)
