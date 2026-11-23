#!/usr/bin/env bash
# Restores the cacerts Secret from a file made by backup-ca.sh, removes
# any self-signed CA that istiod created meanwhile, and restarts istiod.
#
# Usage: ch29/k8s/restore-ca.sh <backup file> <passphrase file>
set -euo pipefail

IN=${1:?backup file}
PASS=${2:?passphrase file}
openssl enc -d -aes-256-cbc -pbkdf2 -pass file:"$PASS" -in "$IN" |
  kubectl apply -f -
kubectl delete secret istio-ca-secret -n istio-system --ignore-not-found # (1)
kubectl rollout restart deployment/istiod -n istio-system
kubectl rollout status deployment/istiod -n istio-system
