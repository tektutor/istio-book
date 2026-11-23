#!/usr/bin/env bash
# Collect mesh security evidence for an audit into a dated folder.
# Needs kubectl and read access to namespaces and Istio security resources.
set -euo pipefail

ROOT_NS="${ROOT_NS:-istio-system}"           # Istio's root namespace
OUT="mesh-evidence-$(date -u +%Y-%m-%d)"
mkdir -p "$OUT"
FINDINGS="$OUT/findings.txt"
: > "$FINDINGS"

finding() { echo "FINDING: $*" | tee -a "$FINDINGS"; }

# 1. Raw copies of every security resource, for the auditor's file.
for kind in peerauthentications authorizationpolicies \
            requestauthentications; do
  kubectl get "$kind.security.istio.io" -A -o yaml > "$OUT/$kind.yaml"
done

# 2. Is mutual TLS STRICT for the whole mesh?
COLS='NAME:.metadata.name,SELECTOR:.spec.selector,MODE:.spec.mtls.mode'
kubectl get peerauthentications.security.istio.io -n "$ROOT_NS" \
  -o custom-columns="$COLS" --no-headers > "$OUT/mesh-mtls.txt"
if awk '$2 == "<none>" && $3 == "STRICT"' "$OUT/mesh-mtls.txt" | grep -q .; then
  echo "mesh-wide mTLS: STRICT" | tee -a "$FINDINGS"
else
  finding "no mesh-wide STRICT PeerAuthentication in $ROOT_NS"
fi

# 3. Every exception to STRICT, with its namespace.
COLS='NAMESPACE:.metadata.namespace,NAME:.metadata.name'
COLS+=',MODE:.spec.mtls.mode,PORTS:.spec.portLevelMtls'
kubectl get peerauthentications.security.istio.io -A \
  -o custom-columns="$COLS" --no-headers > "$OUT/all-mtls.txt"
awk '$3 == "PERMISSIVE" || $3 == "DISABLE" || $4 != "<none>"' \
  "$OUT/all-mtls.txt" | while read -r ns name mode ports; do
  finding "mTLS exception: $ns/$name mode=$mode portLevelMtls=$ports"
done

# 4. Namespaces in the mesh, and how many authorization policies each has.
{
  kubectl get ns -l istio-injection=enabled -o name
  kubectl get ns -l istio.io/rev -o name
  kubectl get ns -l istio.io/dataplane-mode=ambient -o name
} | sed 's#namespace/##' | sort -u > "$OUT/mesh-namespaces.txt"

while read -r ns; do
  count=$(kubectl get authorizationpolicies.security.istio.io -n "$ns" \
            --no-headers 2>/dev/null | wc -l)
  echo "$ns $count" >> "$OUT/policies-per-namespace.txt"
  if [ "$count" -eq 0 ]; then
    finding "namespace $ns is in the mesh but has no AuthorizationPolicy"
  fi
done < "$OUT/mesh-namespaces.txt"

echo "evidence written to $OUT/"
