#!/usr/bin/env bash
# Installs the Argo Rollouts controller and its kubectl plugin, version
# 1.10.1. On macOS, set OS=darwin; on Apple silicon also ARCH=arm64.
set -euo pipefail
V=v1.10.1 OS=${OS:-linux} ARCH=${ARCH:-amd64}
URL=https://github.com/argoproj/argo-rollouts/releases/download/$V
kubectl create namespace argo-rollouts --dry-run=client -o yaml |
  kubectl apply -f -
kubectl apply --server-side -n argo-rollouts -f "$URL/install.yaml"  # (1)
curl -fsSLo kubectl-argo-rollouts "$URL/kubectl-argo-rollouts-$OS-$ARCH"
install -D -m 0755 kubectl-argo-rollouts \
  ~/.local/bin/kubectl-argo-rollouts                               # (2)
rm kubectl-argo-rollouts
kubectl rollout status -n argo-rollouts deploy/argo-rollouts
kubectl argo rollouts version
