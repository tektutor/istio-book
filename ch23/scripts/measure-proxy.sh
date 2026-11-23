#!/usr/bin/env bash
# Prints what one sidecar holds: the number of clusters, listeners and
# routes, the size of its config, and the memory Envoy has allocated.
#
# Usage: ch23/scripts/measure-proxy.sh <namespace> <deployment>
set -euo pipefail

NS=$1
DEPLOY=$2
POD=$(kubectl get pods -n "$NS" -l "app=$DEPLOY" \
        -o jsonpath='{.items[0].metadata.name}')
envoy_admin() {
  kubectl exec -n "$NS" "$POD" -c istio-proxy -- \
    pilot-agent request GET "$1"
}

count() {
  istioctl proxy-config "$1" -n "$NS" "$POD" | tail -n +2 | wc -l
}

echo "clusters:   $(count cluster)"
echo "listeners:  $(count listener)"
echo "routes:     $(count route)"
echo "config:     $(envoy_admin config_dump | wc -c) bytes"         # (1)
echo "memory:     $(envoy_admin memory |
  awk -F'"' '/"allocated"/ {print $4}') bytes allocated"         # (2)
