#!/usr/bin/env bash
# Removes the node affinity that ch44/k8s/break-cni.sh added, so that the
# Istio CNI node agent runs on every node again.
#
# Usage: ch44/k8s/fix-cni.sh
set -euo pipefail

kubectl patch daemonset istio-cni-node -n istio-system --type json \
  -p '[{"op": "remove", "path": "/spec/template/spec/affinity"}]'
kubectl rollout status daemonset istio-cni-node -n istio-system
