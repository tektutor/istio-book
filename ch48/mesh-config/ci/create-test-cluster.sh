#!/usr/bin/env bash
# Creates a throwaway kind cluster with Istio, the shop of Chapter 8,
# inventory v2 of Chapter 18 and the test clients. A GitHub runner has
# Docker, git and kubectl; ci/install-tools.sh adds kind and istioctl.
set -euo pipefail
NODE=kindest/node:v1.35.8
DIGEST=sha256:07b2536e30b803ed61d1677a79df6115f798ce64c80f9e22f6ed45afd09323c0
BOOK=${BOOK:-https://github.com/tektutor/istio-book.git}

kind create cluster --name mesh-ci --image "$NODE@$DIGEST" --wait 120s # (1)
istioctl install -y --set profile=minimal \
  --set meshConfig.accessLogFile=/dev/stdout                        # (2)

git clone -q --depth 1 "$BOOK" book                                 # (3)
for service in inventory orders; do
  docker build -q -t "tektutor/$service:1.0" "book/shop/$service"
  kind load docker-image "tektutor/$service:1.0" --name mesh-ci
done
kubectl apply -f book/ch08/shop/
kubectl apply -f book/ch18/mirror/inventory-v2.yaml
kubectl apply -f tests/namespace.yaml -f tests/clients.yaml
kubectl wait deploy --all -n shop --for=condition=Available --timeout=180s
kubectl wait pod --all -n shop --for=condition=Ready --timeout=180s
kubectl wait pod --all -n legacy --for=condition=Ready --timeout=180s
