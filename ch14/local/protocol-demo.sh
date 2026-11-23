#!/usr/bin/env bash
# Shows, without a cluster, why a server-first protocol hangs on a port
# that Istio must detect. It starts the price feed and two Envoys:
#   17071  the listener Istio builds for the port name "feed" (detection)
#   17072  the listener Istio builds for the port name "tcp-feed" (TCP)
# You need python3, istioctl and an Envoy binary on your PATH.
#
# Usage: ch14/local/protocol-demo.sh       (from the repository root)
set -uo pipefail

FEED=shop/feed/app.py
HERE=ch14/local
cleanup() { kill "${PIDS[@]}" 2>/dev/null; }
trap cleanup EXIT
PIDS=()

python3 "$FEED" serve 17070 > /tmp/feed.log 2>&1 & PIDS+=($!)
envoy -c "$HERE/sniffing-envoy.yaml" --base-id 41 \
  --log-level error > /tmp/envoy-auto.log 2>&1 & PIDS+=($!)
envoy -c "$HERE/tcp-envoy.yaml" --base-id 42 \
  --log-level error > /tmp/envoy-tcp.log 2>&1 & PIDS+=($!)
sleep 2

echo "### 1. Straight to the feed, no proxy"
python3 "$FEED" ask 127.0.0.1 17070 SKU-1

echo "### 2. Through the detecting listener"                  # (1)
python3 "$FEED" ask 127.0.0.1 17071 SKU-1 & ASK=$!
sleep 2                       # read the statistics while the client waits
curl -s 127.0.0.1:19901/stats |
  grep -E "^listener\.127\.0\.0\.1_17071\.downstream_(pre_)?cx_active"
curl -s 127.0.0.1:19901/stats |
  grep -E "^cluster\.feed\.upstream_cx_total"
wait $ASK

echo "### 3. Through the TCP listener"                         # (2)
python3 "$FEED" ask 127.0.0.1 17072 SKU-1
curl -s 127.0.0.1:19902/stats |
  grep -E "^cluster\.feed\.upstream_cx_total"

echo "### 4. HTTP on the detecting listener"                   # (3)
curl -s -m 3 -o /dev/null -w "HTTP status %{http_code}\n" \
  127.0.0.1:17071/
curl -s 127.0.0.1:19901/stats |
  grep -E "^http\.feed_http\.downstream_rq_total"

echo "### 5. The two listeners, as istioctl shows them"            # (4)
curl -s 127.0.0.1:19901/config_dump > /tmp/auto.json
curl -s 127.0.0.1:19902/config_dump > /tmp/tcp.json
istioctl proxy-config listener --file /tmp/auto.json
istioctl proxy-config listener --file /tmp/tcp.json
