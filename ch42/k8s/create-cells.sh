#!/usr/bin/env bash
# Creates three minikube clusters, cell-1, cell-2 and cell-3, on one Docker
# network, gives each a MetalLB address pool, and installs Istio with the
# cell's own trust domain. You can run it again: it starts existing clusters.
#
# Usage: ch42/k8s/create-cells.sh
set -euo pipefail

NET=cells-net
K8S_VERSION=v1.37.0
METALLB=v0.14.9
HERE=$(cd "$(dirname "$0")" && pwd)

start() {                             # start CELL [extra options]
  minikube start -p "$1" --driver=docker --container-runtime=docker \
    --kubernetes-version="$K8S_VERSION" --network="$NET" \
    --cpus=2 --memory=4g "${@:2}"                               # (1)
  kubectl --context "$1" label node "$1" \
    node.kubernetes.io/exclude-from-external-load-balancers-
}
start cell-1                          # minikube creates the network: .2
prefix=$(docker network inspect "$NET" \
  -f '{{(index .IPAM.Config 0).Subnet}}' | cut -d. -f1-3)
start cell-2 --static-ip="$prefix.20"
start cell-3 --static-ip="$prefix.21"

for n in 1 2 3; do
  c=cell-$n
  kubectl --context "$c" apply -f "https://raw.githubusercontent.com/\
metallb/metallb/$METALLB/config/manifests/metallb-native.yaml"
  kubectl --context "$c" wait -n metallb-system --for=condition=Ready \
    pod -l component=controller --timeout=180s
  kubectl --context "$c" apply -f - <<YAML
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: cells
  namespace: metallb-system
spec:
  addresses:
  - $prefix.2${n}0-$prefix.2${n}9
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: cells
  namespace: metallb-system
YAML
  kubectl --context "$c" apply --server-side -f "https://github.com/\
kubernetes-sigs/gateway-api/releases/download/v1.6.3/standard-install.yaml"
  istioctl install --context "$c" -f "$HERE/istio-cell.yaml" \
    --set meshConfig.trustDomain="$c.tektutor.org" \
    --set values.global.multiCluster.clusterName="$c" -y        # (2)
done
echo "cells ready: contexts cell-1, cell-2 and cell-3, network $NET"
