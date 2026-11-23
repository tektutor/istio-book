#!/usr/bin/env bash
# Creates two minikube clusters, cluster1 and cluster2, on one Docker
# network, and gives each a LoadBalancer address pool with MetalLB, so
# that each cluster's east-west gateway is reachable from the other.
# You can run it again: it starts clusters that already exist.
#
# Usage: ch40/k8s/create-clusters.sh
set -euo pipefail

NET=mesh-net                       # the shared Docker network
K8S_VERSION=v1.37.0
METALLB=v0.14.9
declare -A REGION=([cluster1]=us-east [cluster2]=us-west)
declare -A POOL=([cluster1]=200-209 [cluster2]=210-219)        # (1)

# cluster1 first: minikube creates the shared network and gives the node
# the address .2. cluster2 joins the network with an address of its own.
start() {                             # start CLUSTER [extra options]
  local c=$1; shift
  minikube start -p "$c" --driver=docker --container-runtime=docker \
    --kubernetes-version="$K8S_VERSION" --network="$NET" \
    --cpus=4 --memory=6g "$@"                                  # (2)
  kubectl --context "$c" label node "$c" --overwrite \
    topology.kubernetes.io/region="${REGION[$c]}" \
    topology.kubernetes.io/zone="${REGION[$c]}-1a" \
    node.kubernetes.io/exclude-from-external-load-balancers-   # (7)
}
start cluster1
# The first three parts of the network's subnet, such as 192.168.67
prefix=$(docker network inspect "$NET" \
  -f '{{(index .IPAM.Config 0).Subnet}}' | cut -d. -f1-3)       # (3)
start cluster2 --static-ip="$prefix.20"                        # (4)

for c in cluster1 cluster2; do
  kubectl --context "$c" apply -f "https://raw.githubusercontent.com/\
metallb/metallb/$METALLB/config/manifests/metallb-native.yaml"
  kubectl --context "$c" wait -n metallb-system --for=condition=Ready \
    pod -l component=controller --timeout=180s
  first=${POOL[$c]%-*} last=${POOL[$c]#*-}
  kubectl --context "$c" apply -f - <<YAML
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: mesh
  namespace: metallb-system
spec:
  addresses:
  - $prefix.$first-$prefix.$last
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement                                          # (5)
metadata:
  name: mesh
  namespace: metallb-system
YAML
  GWAPI=https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.3
  kubectl --context "$c" apply --server-side \
    -f "$GWAPI/experimental-install.yaml"                        # (6)
done
echo "clusters ready: contexts cluster1 and cluster2, network $NET"
