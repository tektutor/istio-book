#!/usr/bin/env bash
# Stores an intermediate CA from make-intermediate.sh as the Secret
# cacerts, which istiod reads at startup, and restarts istiod.
#
# Usage: ch28/k8s/create-cacerts.sh <directory>
#        example: ch28/k8s/create-cacerts.sh ca-out/lab
set -euo pipefail

DIR=${1:?directory with ca-cert.pem, ca-key.pem, root-cert.pem, cert-chain.pem}
kubectl create secret generic cacerts -n istio-system \
  --from-file=ca-cert.pem="$DIR/ca-cert.pem" \
  --from-file=ca-key.pem="$DIR/ca-key.pem" \
  --from-file=root-cert.pem="$DIR/root-cert.pem" \
  --from-file=cert-chain.pem="$DIR/cert-chain.pem" \
  --dry-run=client -o yaml | kubectl apply -f -                       # (1)
kubectl rollout restart deployment/istiod -n istio-system             # (2)
kubectl rollout status deployment/istiod -n istio-system
