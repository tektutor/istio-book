#!/usr/bin/env bash
# Gives each istiod read access to the other cluster's API server: a
# remote secret for cluster2 goes into cluster1, and the other way round.
#
# Usage: ch40/k8s/remote-secrets.sh
set -euo pipefail

for pair in "cluster1 cluster2" "cluster2 cluster1"; do
  read -r from to <<< "$pair"
  server="https://$(minikube ip -p "$from"):8443"               # (1)
  istioctl create-remote-secret --context="$from" --name="$from" \
    --server="$server" |
    kubectl --context="$to" apply -f -                          # (2)
done
