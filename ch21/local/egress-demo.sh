#!/usr/bin/env bash
# Shows, without a cluster, what a sidecar does with outbound traffic:
# REGISTRY_ONLY for an unknown HTTP host and for an unknown TLS
# destination, TLS origination for a known external host, and a TLS
# connection sent through a corporate proxy with HTTP CONNECT.
# You need openssl, python3, curl and Envoy on your PATH.
#
# Usage: ch21/local/egress-demo.sh       (from the repository root)
set -uo pipefail

C=/tmp/ch21-certs                                              # (1)
mkdir -p $C
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes \
  -keyout $C/lab-ca.key -out $C/lab-ca.crt -days 7 \
  -subj "/CN=Lab CA" 2>/dev/null
openssl req -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes \
  -keyout $C/api.key -out $C/api.csr \
  -subj "/CN=api.partner.tektutor.test" 2>/dev/null
openssl x509 -req -in $C/api.csr -CA $C/lab-ca.crt -CAkey $C/lab-ca.key \
  -CAcreateserial -out $C/api.crt -days 7 \
  -extfile <(echo "subjectAltName=DNS:api.partner.tektutor.test") 2>/dev/null

PIDS=()
cleanup() { kill "${PIDS[@]}" 2>/dev/null; }
trap cleanup EXIT
python3 ch21/local/partner_api.py $C/api.crt $C/api.key & PIDS+=($!)
python3 ch21/local/corp_proxy.py > /tmp/ch21-proxy.log & PIDS+=($!)
rm -f /tmp/ch21-access.log
envoy -c ch21/local/egress-envoy.yaml --base-id 46 --log-level error \
  --file-flush-interval-msec 200 > /tmp/envoy-egress.log 2>&1 & PIDS+=($!)
sleep 2
N=(--noproxy "*" -s -m 5)

echo "### 1. Plain HTTP to an unknown host"
curl "${N[@]}" -o /dev/null -w "status %{http_code}\n" \
  -H "Host: unknown.tektutor.test" http://127.0.0.1:18700/
echo "### 2. TLS to an unknown destination"
curl "${N[@]}" -o /dev/null -w "status %{http_code}\n" \
  --resolve unknown.tektutor.test:18701:127.0.0.1 \
  https://unknown.tektutor.test:18701/ || echo "curl exit code $?"   # (2)
echo "### 3. Plain HTTP from the app, TLS on the wire"
curl "${N[@]}" -H "Host: api.partner.tektutor.test" \
  http://127.0.0.1:18702/v1/rates
echo "### 4. TLS from the app, through the corporate proxy"
curl "${N[@]}" --cacert $C/lab-ca.crt \
  --resolve api.partner.tektutor.test:18703:127.0.0.1 \
  https://api.partner.tektutor.test:18703/v1/rates                       # (3)
sleep 1
echo "### The corporate proxy's log"
cat /tmp/ch21-proxy.log
echo "### The sidecar's access log"
cat /tmp/ch21-access.log
echo "### The sidecar's counter for refused connections"
curl "${N[@]}" http://127.0.0.1:19906/stats |
  grep "cluster.BlackHoleCluster.upstream_cx_none_healthy"     # (4)
