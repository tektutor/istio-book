#!/usr/bin/env bash
# Restarts every workload that holds a mesh certificate, so that each one
# gets a new certificate from the current CA: ztunnel, the Deployments and
# StatefulSets of every mesh namespace, and the gateways in "ingress".
#
# Usage: ch28/k8s/restart-mesh.sh       (with kubectl pointed at the cluster)
set -euo pipefail

for zns in istio-system ztunnel; do                                  # (1)
  want=$(kubectl get daemonset ztunnel -n "$zns" \
    -o jsonpath='{.status.desiredNumberScheduled}' 2> /dev/null || true)
  if [[ ${want:-0} -gt 0 ]]; then              # a DaemonSet with pods
    # Delete the pods instead of "rollout restart": on OpenShift, the Sail
    # Operator owns the DaemonSet and undoes the restart annotation. The
    # DaemonSet's own selector finds its pods.
    sel=$(kubectl get daemonset ztunnel -n "$zns" -o json |
      jq -r '.spec.selector.matchLabels | to_entries
             | map("\(.key)=\(.value)") | join(",")')
    if [[ -z $(kubectl get pod -n "$zns" -l "$sel" -o name) ]]; then
      echo "ztunnel in $zns has no pods: skipped"; continue
    fi
    kubectl delete pod -n "$zns" -l "$sel"
    sleep 10
    kubectl wait pod -n "$zns" -l "$sel" --for=condition=Ready --timeout=300s
  fi
done
NAMESPACES=$( { kubectl get ns -l istio-injection=enabled -o name
                kubectl get ns -l istio.io/rev -o name
                kubectl get ns -l istio.io/dataplane-mode=ambient -o name
                kubectl get ns ingress -o name 2>/dev/null || true
              } | cut -d/ -f2 | sort -u )                              # (2)
for ns in $NAMESPACES; do
  for w in $(kubectl get deployments,statefulsets -n "$ns" -o name); do
    kubectl rollout restart -n "$ns" "$w"
  done
  for w in $(kubectl get deployments,statefulsets -n "$ns" -o name); do
    kubectl rollout status -n "$ns" "$w" --timeout 300s                # (3)
  done
  for i in $(seq 60); do                      # until the old pods are gone
    [[ -z $(kubectl get pods -n "$ns" -o \
      jsonpath='{.items[?(@.metadata.deletionTimestamp)].metadata.name}') ]] &&
      break
    sleep 2
  done
done
