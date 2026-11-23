#!/usr/bin/env bash
# Sends five requests from three callers to the inventory sidecar with
# Istio's RBAC filters, then shows the access log and the counters of
# the dry-run policy.
# You need Envoy, openssl and python3 with cryptography.
#
# Usage: ch31/local/authz-demo.sh       (from the repository root)
set -uo pipefail

CERTS=/tmp/ch31-certs
CA=$(mktemp -d)
rm -rf $CERTS /tmp/ch31-access.log; mkdir -p $CERTS
ch28/ca/make-root.sh "$CA" > /dev/null
ch28/ca/make-intermediate.sh lab "$CA" > /dev/null
for sa in inventory orders cart curl; do
  python3 ch28/ca/issue_workload_cert.py "$CA/lab" shop $sa > /dev/null
  cp -r "$CA/lab/shop-$sa" $CERTS/$sa
done
cp "$CA/lab/root-cert.pem" $CERTS/
envoy -c ch31/local/authz-envoy.yaml --base-id 64 --log-level error \
  --file-flush-interval-msec 100 > /tmp/ch31-envoy.log 2>&1 &
ENVOY=$!
trap 'kill $ENVOY 2>/dev/null; rm -rf "$CA"' EXIT
until curl -s http://127.0.0.1:19933/ready 2>/dev/null | grep -q LIVE
do kill -0 $ENVOY || exit 1; sleep 0.2; done

call() {                     # call <caller> <method> <path>
  printf "%-7s %-5s %-22s -> " "$1" "$2" "$3"
  curl -s -o /tmp/ch31-body.txt -w "%{http_code}" -X "$2" \
    -H "x-caller: $1" "http://127.0.0.1:18950$3"
  echo " $(head -c 40 /tmp/ch31-body.txt | tr -d '\n')"
}
echo "### Five requests"
call orders GET  /api/stock/SKU-1                              # (1)
call cart   GET  /api/stock/SKU-1
call curl   GET  /api/stock/SKU-1
call orders POST /api/stock/SKU-1
call orders GET  /admin/faults
sleep 0.5
echo "### The inventory access log"
sed 's/spiffe:\/\/cluster.local\/ns\/shop\/sa\//sa:/' /tmp/ch31-access.log |
  fold -w 76                                                   # (2)
echo "### The dry-run counters"
curl -s http://127.0.0.1:19933/stats | grep 'istio_dry_run_deny_'   # (3)
