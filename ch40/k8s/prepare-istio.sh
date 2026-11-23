#!/usr/bin/env bash
# Prepares both clusters for Istio before the installation: one root CA
# for the mesh, an intermediate CA per cluster in the Secret cacerts,
# and the network label on the namespace istio-system.
#
# Usage: ch40/k8s/prepare-istio.sh [directory]   (default: ca-out)
set -euo pipefail

OUT=${1:-ca-out}
HERE=$(cd "$(dirname "$0")/../.." && pwd)        # the book's code folder
[ -f "$OUT/root/root-cert.pem" ] ||
  "$HERE/ch28/ca/make-root.sh" "$OUT" "TekTutor Mesh Root CA"   # (1)

for n in 1 2; do
  c=cluster$n
  "$HERE/ch28/ca/make-intermediate.sh" "$c" "$OUT"              # (2)
  kubectl --context "$c" create namespace istio-system \
    --dry-run=client -o yaml | kubectl --context "$c" apply -f -
  kubectl --context "$c" label namespace istio-system --overwrite \
    topology.istio.io/network="network$n"                       # (3)
  kubectl --context "$c" create secret generic cacerts -n istio-system \
    --from-file="$OUT/$c/ca-cert.pem" --from-file="$OUT/$c/ca-key.pem" \
    --from-file="$OUT/$c/root-cert.pem" \
    --from-file="$OUT/$c/cert-chain.pem" \
    --dry-run=client -o yaml | kubectl --context "$c" apply -f -  # (4)
done
