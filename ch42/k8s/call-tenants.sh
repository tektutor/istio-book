#!/usr/bin/env bash
# Calls the cell router once for every tenant, with the tenant's token,
# from a curl container on the cells' Docker network, and prints the cell
# that answered.
#
# Usage: ch42/k8s/call-tenants.sh [tokens directory]   (default: tokens)
set -euo pipefail
DIR=${1:-tokens}
ROUTER=$(kubectl --context cell-1 get gateway cell-router -n router \
  -o jsonpath='{.status.addresses[0].value}')
for f in "$DIR"/*.jwt; do
  tenant=$(basename "$f" .jwt)
  printf '%-10s ' "$tenant"
  docker run --rm --network cells-net curlimages/curl:8.16.0 -s -m 5 \
    -w ' %{http_code}\n' -H "authorization: Bearer $(cat "$f")" \
    "http://$ROUTER/"                                           # (1)
done
