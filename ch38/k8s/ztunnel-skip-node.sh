#!/usr/bin/env bash
# Removes ztunnel from one node, as a node with a failed ztunnel looks,
# or puts it back. A node affinity keeps the DaemonSet's pod off the node.
#
# Usage: ch38/k8s/ztunnel-skip-node.sh NODE | --restore
set -euo pipefail
[[ $# -eq 1 ]] || { echo "usage: $0 NODE | --restore" >&2; exit 2; }
NS=${ZTUNNEL_NS:-istio-system}
if [[ ${1:-} == --restore ]]; then
  kubectl patch daemonset ztunnel -n "$NS" --type json \
    -p '[{"op": "remove", "path": "/spec/template/spec/affinity"}]'
else
  kubectl patch daemonset ztunnel -n "$NS" --type merge -p "{\"spec\":
    {\"template\": {\"spec\": {\"affinity\": {\"nodeAffinity\":
    {\"requiredDuringSchedulingIgnoredDuringExecution\":
    {\"nodeSelectorTerms\": [{\"matchExpressions\": [{\"key\":
    \"kubernetes.io/hostname\", \"operator\": \"NotIn\",
    \"values\": [\"$1\"]}]}]}}}}}}}"                                # (1)
fi
kubectl rollout status daemonset/ztunnel -n "$NS"
