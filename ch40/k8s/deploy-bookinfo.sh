#!/usr/bin/env bash
# Splits Bookinfo over the two clusters. Every Service and service
# account exists in both clusters; the Deployments do not:
#   cluster1: productpage, details, reviews-v1, reviews-v2, curl
#   cluster2: reviews-v3, ratings
#
# Usage: ch40/k8s/deploy-bookinfo.sh [label]
#   label: istio-injection=enabled (default) or
#          istio.io/dataplane-mode=ambient
set -euo pipefail

LABEL=${1:-istio-injection=enabled}
APP="$ISTIO_HOME/samples/bookinfo/platform/kube/bookinfo.yaml"

for c in cluster1 cluster2; do
  kubectl --context "$c" create namespace bookinfo \
    --dry-run=client -o yaml | kubectl --context "$c" apply -f -
  kubectl --context "$c" label namespace bookinfo --overwrite "$LABEL"
  kubectl --context "$c" apply -n bookinfo -f "$APP" -l service  # (1)
  kubectl --context "$c" apply -n bookinfo -f "$APP" -l account
done
kubectl --context cluster1 apply -n bookinfo -f "$APP" \
  -l 'app in (productpage,details)'
kubectl --context cluster1 apply -n bookinfo -f "$APP" \
  -l 'app=reviews,version in (v1,v2)'
kubectl --context cluster1 apply -n bookinfo \
  -f "$ISTIO_HOME/samples/curl/curl.yaml"                       # (2)
kubectl --context cluster2 apply -n bookinfo -f "$APP" \
  -l 'app=reviews,version=v3'
kubectl --context cluster2 apply -n bookinfo -f "$APP" -l app=ratings

for c in cluster1 cluster2; do
  kubectl --context "$c" wait -n bookinfo --for=condition=Available \
    deployment --all --timeout=300s
done
