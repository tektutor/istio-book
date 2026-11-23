#!/usr/bin/env bash
# Moves shop workloads back to sidecars: the injection label returns, and
# each restarted pod gets its sidecar again. Without arguments, it rolls
# back every workload; with arguments, only those.
#
# Usage: ch37/k8s/rollback-shop.sh [workload ...]
set -euo pipefail
NS=shop
WORKLOADS=${*:-"deploy/inventory deploy/stock deploy/feed deploy/orders
  deploy/cart deploy/frontend deploy/feed-client statefulset/postgres
  deploy/fortio deploy/curl"}

if [[ $# -eq 0 ]]; then                       # (1)
  kubectl label namespace "$NS" istio.io/dataplane-mode- \
    istio-injection=enabled --overwrite
else
  for w in $WORKLOADS; do                     # (2)
    kubectl patch "$w" -n "$NS" --type merge -p '{"spec":{"template":
      {"metadata":{"labels":{"sidecar.istio.io/inject":"true",
      "istio.io/dataplane-mode":"none"}}}}}'
  done
fi
for w in $WORKLOADS; do
  kubectl get "$w" -n "$NS" > /dev/null 2>&1 || continue      # (3)
  kubectl rollout restart "$w" -n "$NS"
  kubectl rollout status "$w" -n "$NS" --timeout=180s
done
