#!/usr/bin/env bash
# Calls the inventory sidecar in PERMISSIVE and STRICT mode, from the
# orders sidecar and from a client without one, and captures the packets.
# You need Envoy, tcpdump, openssl and python3 with cryptography. tcpdump
# needs root, so the script uses sudo when you are not root.
#
# Usage: ch30/local/mtls-demo.sh       (from the repository root)
set -uo pipefail

CERTS=/tmp/ch30-certs
CA=$(mktemp -d)
rm -rf $CERTS /tmp/ch30-access.log; mkdir -p $CERTS
ch28/ca/make-root.sh "$CA" > /dev/null
ch28/ca/make-intermediate.sh lab "$CA" > /dev/null
for sa in orders inventory; do
  python3 ch28/ca/issue_workload_cert.py "$CA/lab" shop $sa > /dev/null
  cp -r "$CA/lab/shop-$sa" $CERTS/$sa
done
cp "$CA/lab/root-cert.pem" $CERTS/
envoy -c ch30/local/mtls-envoy.yaml --base-id 60 --log-level error \
  --file-flush-interval-msec 100 > /tmp/ch30-envoy.log 2>&1 &
ENVOY=$!
trap 'kill $ENVOY 2>/dev/null; rm -rf "$CA"' EXIT
until curl -s http://127.0.0.1:19932/ready 2>/dev/null | grep -q LIVE
do kill -0 $ENVOY || exit 1; sleep 0.2; done

call() {                                                        # (1)
  local out
  out=$(curl -s -o /dev/null -w "%{http_code}" "$1/api/stock/SKU-1")
  local rc=$?
  if [ "$rc" = 0 ]; then echo "HTTP $out"
  else echo "no answer, curl exit $rc"; fi
}
echo "### 1. orders sidecar -> PERMISSIVE: $(call http://127.0.0.1:18800)"
echo "### 2. no sidecar     -> PERMISSIVE: $(call http://127.0.0.1:18801)"
echo "### 3. orders sidecar -> STRICT:     $(call http://127.0.0.1:18802)"
echo "### 4. no sidecar     -> STRICT:     $(call http://127.0.0.1:18803)"
echo "### 5. orders sidecar -> STRICT, pqc: $(call http://127.0.0.1:18804)"
sleep 0.5
echo "### The inventory access log: port, filter chain, TLS, caller"
cat /tmp/ch30-access.log                                        # (2)

TCPDUMP=tcpdump; [ "$(id -u)" = 0 ] || TCPDUMP="sudo tcpdump"
capture() {                                                     # (3)
  $TCPDUMP -i lo -l -A -s 0 'tcp port 18801' \
    > /tmp/ch30-capture.txt 2>/dev/null &
  local tcp=$!
  sleep 1; curl -s -o /dev/null "$1/api/stock/SKU-1"; sleep 1
  $([ "$(id -u)" = 0 ] || echo sudo) kill $tcp; wait $tcp 2>/dev/null
  echo "$(grep -c 'GET /api/stock/SKU-1' /tmp/ch30-capture.txt) lines" \
       "show the path, $(grep -c 'available' /tmp/ch30-capture.txt) the answer"
}
echo "### Key exchange groups used by the inventory listeners"
curl -s http://127.0.0.1:19932/stats | grep -E '^listener\.127.*ssl\.curves' |
  sed 's/^listener\.127\.0\.0\.1_//'                           # (4)
echo "### 6. Capture, plain text: $(capture http://127.0.0.1:18801)"
echo "### 7. Capture, mutual TLS: $(capture http://127.0.0.1:18800)"
