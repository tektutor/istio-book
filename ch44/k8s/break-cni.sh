#!/usr/bin/env bash
# Breaks the Istio CNI node agent on one node, chosen at random and not
# printed, so that you must find it from the symptoms. The agent's pod
# leaves that node and removes the istio-cni plugin from its CNI config,
# as it does in a failed rollout or an unplanned DaemonSet change.
#
# Usage: ch44/k8s/break-cni.sh            (ch44/k8s/fix-cni.sh undoes it)
set -euo pipefail

node=$(kubectl get nodes -o name | cut -d/ -f2 | shuf -n 1)     # (1)
kubectl patch daemonset istio-cni-node -n istio-system --type merge -p "
spec:
  template:
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: kubernetes.io/hostname
                operator: NotIn
                values: [\"$node\"]" > /dev/null                 # (2)
kubectl rollout status daemonset istio-cni-node -n istio-system \
  --timeout=180s > /dev/null
echo "The Istio CNI agent is broken on one node."
