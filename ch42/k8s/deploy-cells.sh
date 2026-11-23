#!/usr/bin/env bash
# Deploys the cell application and isolation policies into each cell, and
# the cell router into cell-1: tokens, route and the addresses of the
# three cell gateways.
#
# Usage: ch42/k8s/deploy-cells.sh
set -euo pipefail
CODE=$(cd "$(dirname "$0")/.." && pwd)
declare -A GW

for n in 1 2 3; do
  c=cell-$n
  sed "s/CELL_NAME/$c/" "$CODE/cell/namespace.yaml" |
    kubectl --context "$c" apply -f -
  sed "s/CELL_NAME/$c/" "$CODE/cell/app.yaml" |
    kubectl --context "$c" apply -n shop -f -
  sed "s/CELL_NAME/$c/" "$CODE/cell/isolation.yaml" |
    kubectl --context "$c" apply -f -
  kubectl --context "$c" wait -n shop --for=condition=Programmed \
    gateway/cell-gw --timeout=180s
  kubectl --context "$c" rollout status deployment/cell-app -n shop \
    --timeout=180s                                              # (1)
  GW[$c]=$(kubectl --context "$c" get gateway cell-gw -n shop \
    -o jsonpath='{.status.addresses[0].value}')                 # (2)
done

R=$CODE/router
kubectl --context cell-1 apply -f "$R/gateway.yaml"
python3 "$R/make-tokens.py" tokens                              # (3)
kubectl --context cell-1 apply -f tokens/request-authn.yaml \
  -f "$R/require-jwt.yaml"
sed -e "s/CELL1_GW/${GW[cell-1]}/" -e "s/CELL2_GW/${GW[cell-2]}/" \
    -e "s/CELL3_GW/${GW[cell-3]}/" "$R/cells.yaml" |
  kubectl --context cell-1 apply -f -
python3 "$R/gen-route.py" | kubectl --context cell-1 apply -f -
kubectl --context cell-1 wait -n router --for=condition=Programmed \
  gateway/cell-router --timeout=180s
echo "cell gateways: ${GW[cell-1]} ${GW[cell-2]} ${GW[cell-3]}"
