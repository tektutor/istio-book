#!/usr/bin/env bash
# Creates the upgrade lab: a minikube cluster "upgrade" with Istio 1.30.5
# as revision 1-30-5, the tags prod-stable and prod-canary, Bookinfo on
# prod-stable behind a Gateway API gateway, and Fortio in the namespace
# load, also in the mesh, as the client and the canary of the upgrade.
#
# Usage: ch43/k8s/create-upgrade-lab.sh       (needs $ISTIO_HOME, 1.31.1)
set -euo pipefail
CODE=$(cd "$(dirname "$0")/../.." && pwd)
OLD=1.30.5

minikube start -p upgrade --driver=docker --container-runtime=docker \
  --kubernetes-version=v1.36.0 --cpus=4 --memory=8g             # (1)
kubectl config use-context upgrade
kubectl apply --server-side -f "https://github.com/kubernetes-sigs/\
gateway-api/releases/download/v1.6.3/standard-install.yaml"

if [ ! -x "istio-$OLD/bin/istioctl" ]; then                     # (2)
  mkdir -p "istio-$OLD/bin"
  curl -sL "https://github.com/istio/istio/releases/download/$OLD/\
istioctl-$OLD-linux-amd64.tar.gz" | tar xz -C "istio-$OLD/bin"
fi
"istio-$OLD/bin/istioctl" install -y \
  -f "$CODE/ch43/istio/control-plane.yaml" --set revision=1-30-5
istioctl tag set prod-stable --revision 1-30-5                  # (3)
istioctl tag set prod-canary --revision 1-30-5

kubectl create namespace bookinfo
kubectl label namespace bookinfo istio.io/rev=prod-stable \
  tektutor.org/ingress=allowed
sed 's#registry.istio.io/release#docker.io/istio#' \
  "$ISTIO_HOME/samples/bookinfo/platform/kube/bookinfo.yaml" |
  kubectl apply -n bookinfo -f -                                # (4)
kubectl apply -f "$CODE/ch15/gateway/public-gateway.yaml"
kubectl label gateways.gateway.networking.k8s.io public -n ingress \
  istio.io/rev=prod-stable                                      # (5)
kubectl apply -f "$CODE/ch15/gateway/bookinfo-route.yaml"
kubectl create namespace load
kubectl label namespace load istio.io/rev=prod-stable
kubectl create deployment fortio -n load --image=fortio/fortio:1.76.0 \
  -- fortio server                                              # (6)
kubectl wait --for=condition=Available deployment --all -n bookinfo \
  --timeout=300s
kubectl wait --for=condition=Available deployment/fortio -n load \
  --timeout=120s
echo "upgrade lab ready: Istio $OLD as revision 1-30-5"
