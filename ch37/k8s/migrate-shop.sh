#!/usr/bin/env bash
# Moves the workloads of the shop namespace from sidecars to ambient mode
# one at a time: restart, wait, check that ztunnel took the new pods, and
# call the shop through the gateway. Stops at the first failure, so you
# can roll back that workload with rollback-shop.sh. The default order
# moves the clients first and inventory, which only receives, last.
#
# Usage: ch37/k8s/migrate-shop.sh [workload ...]   (default: all of them)
# On OpenShift, set GATEWAY_IP to the router's address and ZTUNNEL_NS to
# the namespace of ztunnel:  GATEWAY_IP=$(crc ip) ZTUNNEL_NS=ztunnel
set -euo pipefail
NS=shop
GW=${GATEWAY_IP:-$(kubectl get gateway public -n ingress \
  -o jsonpath='{.status.addresses[0].value}')}
ZTNS=${ZTUNNEL_NS:-istio-system}
WORKLOADS=${*:-"deploy/curl deploy/fortio deploy/feed-client deploy/frontend
  deploy/cart deploy/orders deploy/feed deploy/stock statefulset/postgres
  deploy/inventory"}

check_shop() {                                # the cart and an order answer
  curl -sk -o /dev/null -w '%{http_code} ' \
    --resolve "shop.tektutor.test:443:$GW" \
    https://shop.tektutor.test/api/cart/kayal
  kubectl exec -n "$NS" deploy/curl -c curl -- curl -s -o /dev/null \
    -w '%{http_code}' http://orders:8080/api/orders/7  # orders -> inventory
}

kubectl label namespace "$NS" istio-injection- \
  istio.io/dataplane-mode=ambient --overwrite                  # (1)
for w in $WORKLOADS; do
  echo "### $w"
  if ! kubectl get "$w" -n "$NS" > /dev/null 2>&1; then          # (2)
    echo "skipped: no $w in $NS"; continue
  fi
  kubectl rollout restart "$w" -n "$NS"
  kubectl rollout status "$w" -n "$NS" --timeout=180s
  app=$(kubectl get "$w" -n "$NS" -o jsonpath='{.spec.selector.matchLabels.app}')
  pods=$(kubectl get pods -n "$NS" -l "app=$app" -o jsonpath='{range .items[*]}
    {.metadata.name} {.metadata.deletionTimestamp}{"\n"}{end}' |
    awk 'NF == 1 {print $1}')                 # skip pods that are going away
  for p in $pods; do                          # (3)
    containers=$(kubectl get pod "$p" -n "$NS" \
      -o jsonpath='{.spec.containers[*].name} {.spec.initContainers[*].name}')
    if [[ " $containers " == *" istio-proxy "* ]]; then
      echo "$p still has a sidecar"; exit 1
    fi
    istioctl ztunnel-config workloads --workload-namespace "$NS" \
      --namespace "$ZTNS" |
      grep -q "$p .*HBONE" || { echo "$p is not in ambient mode"; exit 1; }
  done
  code=$(check_shop)
  echo "pods: $pods; shop answers $code"
  [[ $code == "200 200" ]] || exit 1         # (4)
done
