#!/usr/bin/env bash
# Creates the failure lab: a three-node minikube cluster "meshfail" with
# istiod and the Istio CNI node agent, and the namespace shop with the
# server and client of ch44/k8s/apps.yaml. Run it from the repository
# root; it needs about 10 GB of free memory.
#
# Usage: ch44/k8s/create-fail-lab.sh
set -euo pipefail

minikube start -p meshfail --nodes 3 --driver=docker \
  --kubernetes-version=v1.36.0 --cpus=2 --memory=3g            # (1)
kubectl config use-context meshfail
istioctl install -y -f ch44/istio/control-plane.yaml          # (2)
kubectl rollout status daemonset istio-cni-node -n istio-system

kubectl create namespace shop
kubectl label namespace shop istio-injection=enabled
kubectl create configmap lab-app -n shop \
  --from-file=ch44/app/server.py --from-file=ch44/app/poll.py   # (3)
kubectl apply -f ch44/k8s/apps.yaml
kubectl wait --for=condition=Available deployment --all -n shop \
  --timeout=300s
kubectl get pods -n shop -o wide
echo "failure lab ready"
