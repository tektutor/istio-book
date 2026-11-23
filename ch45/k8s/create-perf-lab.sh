#!/usr/bin/env bash
# Creates the benchmark lab: a quiet three-node minikube cluster "perf"
# with Istio's ambient profile, which supports sidecars too, the
# Prometheus add-on, and the three benchmark namespaces. Run it from the
# repository root; it needs 4 CPUs and 4 GB per node.
#
# Usage: ch45/k8s/create-perf-lab.sh        (needs $ISTIO_HOME, 1.31.1)
set -euo pipefail

minikube start -p perf --nodes 3 --driver=docker \
  --kubernetes-version=v1.36.0 --cpus=4 --memory=4g             # (1)
kubectl config use-context perf
kubectl taint nodes perf-m02 perf-m03 bench=dedicated:NoSchedule  # (2)
istioctl install -y --set profile=ambient --set hub=docker.io/istio  # (3)
kubectl apply -f "$ISTIO_HOME/samples/addons/prometheus.yaml"
kubectl rollout status deployment prometheus -n istio-system

for ns in bench-nomesh bench-sidecar bench-ambient; do
  kubectl create namespace "$ns"
done
kubectl label namespace bench-sidecar istio-injection=enabled
kubectl label namespace bench-ambient istio.io/dataplane-mode=ambient
for ns in bench-nomesh bench-sidecar bench-ambient; do
  kubectl apply -n "$ns" -f ch45/k8s/bench-apps.yaml             # (4)
done
for ns in bench-nomesh bench-sidecar bench-ambient; do
  kubectl wait --for=condition=Available deployment --all -n "$ns" \
    --timeout=300s
done
echo "perf lab ready"
