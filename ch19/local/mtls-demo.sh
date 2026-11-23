#!/usr/bin/env bash
# Shows, without a cluster, what client certificate validation at a
# gateway does. Three clients call two listeners: one without a
# certificate, Acme with a certificate from the partner CA, and a rogue
# client with a certificate from an unknown CA.
# You need openssl, python3, curl and Envoy on your PATH.
#
# Usage: ch19/local/mtls-demo.sh       (from the repository root)
set -uo pipefail

C=/tmp/ch19-certs
ch19/local/make-certs.sh $C > /dev/null
PIDS=()
cleanup() { kill "${PIDS[@]}" 2>/dev/null; }
trap cleanup EXIT
python3 ch19/local/echo.py 18080 & PIDS+=($!)
envoy -c ch19/local/mtls-envoy.yaml --base-id 45 --log-level error \
  > /tmp/envoy-mtls.log 2>&1 & PIDS+=($!)
sleep 2

call() {                    # call PORT [client certificate name]
  local cert=()
  [ -n "${2:-}" ] && cert=(--cert "$C/$2.crt" --key "$C/$2.key")
  curl -sS --noproxy "*" --cacert $C/lab-ca.crt "${cert[@]}" \
    --resolve partner.tektutor.test:$1:127.0.0.1 \
    "https://partner.tektutor.test:$1/api/orders/1" 2>&1 | tail -1
}

for port in 18443 18444; do
  echo "### port $port, no certificate:   $(call $port)"
  echo "### port $port, Acme certificate:  $(call $port acme)"
  echo "### port $port, rogue certificate: $(call $port rogue)"
done
