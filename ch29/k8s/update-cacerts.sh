#!/usr/bin/env bash
# Replaces the cacerts Secret with a signing intermediate and a separate
# file of trusted roots, without restarting istiod. With
# ISTIO_MULTIROOT_MESH, istiod reloads both from the mounted files.
#
# Usage: ch29/k8s/update-cacerts.sh <intermediate directory> <roots file>
#        example: ch29/k8s/update-cacerts.sh ca-out/lab roots-ab.pem
set -euo pipefail

DIR=${1:?directory with ca-cert.pem, ca-key.pem and cert-chain.pem}
ROOTS=${2:?file with the trusted roots}
SINCE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
kubectl create secret generic cacerts -n istio-system \
  --from-file=ca-cert.pem="$DIR/ca-cert.pem" \
  --from-file=ca-key.pem="$DIR/ca-key.pem" \
  --from-file=cert-chain.pem="$DIR/cert-chain.pem" \
  --from-file=root-cert.pem="$ROOTS" \
  --dry-run=client -o yaml | kubectl apply -f -                       # (1)
echo "Waiting for istiod to reload the Secret's files..."
for i in $(seq 60); do                                                # (2)
  LOG=$(kubectl logs -n istio-system deploy/istiod --since-time="$SINCE")
  if echo "$LOG" | grep -q 'ROOT-CA not supported\|Failed to update new'; then
    echo "istiod refused the new files:"
    echo "$LOG" | grep 'ROOT-CA\|Failed to update new'
    exit 1
  fi
  if echo "$LOG" | grep -q 'detected the newly added intermediate CA'; then
    echo "istiod loaded the new files."
    exit 0
  fi
  sleep 5
done
echo "istiod did not reload the files within 5 minutes."
exit 1
