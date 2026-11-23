#!/usr/bin/env bash
# Sends ten requests, 1.5 seconds apart, through each inbound listener
# to an application with a keep-alive timeout of one second.
# You need Envoy and python3 on your PATH.
#
# Usage: ch27/local/uc-demo.sh       (from the repository root)
set -uo pipefail

PIDS=()
cleanup() { kill "${PIDS[@]}" 2>/dev/null; }
trap cleanup EXIT
python3 ch27/local/keepalive_server.py 18401 1.0 & PIDS+=($!)
rm -f /tmp/ch27-access.log
envoy -c ch27/local/uc-envoy.yaml --base-id 55 --log-level error \
  --file-flush-interval-msec 200 > /tmp/ch27-envoy.log 2>&1 & PIDS+=($!)
until curl -s http://127.0.0.1:19927/ready 2>/dev/null | grep -q LIVE
do kill -0 "${PIDS[@]}" || exit 1; sleep 0.2; done

for port in 18400 18402; do
  echo "### Port $port: ten requests, 1.5 s apart"
  for i in $(seq 1 10); do
    curl -s -o /dev/null -w "%{http_code} " \
      http://127.0.0.1:$port/api/stock/SKU-1
    sleep 1.5                                                  # (1)
  done
  echo
done
sleep 1
echo "### The access log, counted"
sort /tmp/ch27-access.log | uniq -c
