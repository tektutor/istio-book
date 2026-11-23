#!/usr/bin/env bash
# Shows what a gateway does when its Wasm plugin cannot load: the module
# pull fails, or the plugin rejects its configuration. Envoy reads the
# extension config from a file here; in Istio, istiod and istio-agent
# send the same resources over xDS. You need envoy-contrib and curl.
#
# Usage: ch39/local/ecds-demo.sh   (from the repository root, after
#        building the Rust module with tenant-rust/build.sh)
set -euo pipefail
CODE=$(cd "$(dirname "$0")/.." && pwd)
OUT=${OUT:-/tmp/ch39-ecds}
ENVOY=${ENVOY:-envoy-contrib}
MODULE=$CODE/tenant-rust/target/wasm32-unknown-unknown/release
MODULE=$MODULE/tenant_check.wasm
GOOD='{"header": "x-tenant", "tenants": ["acme", "globex"]}'
BAD='{"header": "x-tenant", "tenants": "acme"}'    # (1)
mkdir -p "$OUT"
PID=
trap '[[ -n $PID ]] && kill $PID 2>/dev/null; true' EXIT

push() {                                      # push FILE [CONFIG]
  sed -e "s|MODULE|$MODULE|" -e "s|CONFIG|${2:-}|" \
    "$CODE/local/ecds/$1" > "$OUT/next.yaml"
  mv "$OUT/next.yaml" "$OUT/ecds.yaml"        # (2)
  sleep 1.5
}

start() {
  [[ -n $PID ]] && { kill $PID; wait $PID 2>/dev/null || true; }
  sed "s|ECDS_FILE|$OUT/ecds.yaml|" "$CODE/local/envoy-ecds.yaml" \
    > "$OUT/envoy.yaml"
  "$ENVOY" -c "$OUT/envoy.yaml" --log-level warn > "$OUT/envoy.log" 2>&1 &
  PID=$!
  until curl -s localhost:18601/ready | grep -q LIVE; do sleep 0.2; done
}

ask() {
  for h in "" "x-tenant: acme"; do
    printf '  %-16s %s\n' "${h:-no header}" "$(curl -s -w ' (%{http_code})' \
      ${h:+-H "$h"} http://127.0.0.1:18600/ | tr -d '\n')"
  done
}

ecds_stat() {                                 # ecds_stat NAME
  curl -s localhost:18601/stats |
    awk -v n="$1" -F': ' '$1 ~ "tenant-check." n "$" {print "  " n ": " $2}'
}

echo "### 1. The pull failed, failStrategy FAIL_CLOSE"
push deny.yaml; start; ask
echo "### 2. The pull failed, failStrategy FAIL_OPEN"
push allow.yaml; ask
echo "### 3. The module loads"
push wasm.yaml "$GOOD"; ask
echo "### 4. A new configuration that the plugin rejects"
push wasm.yaml "$BAD"; ask; ecds_stat update_rejected
grep -m1 -o 'wasm log.*' "$OUT/envoy.log" | sed 's/^/  /'
echo "### 5. A new gateway pod gets the same configuration"
start; ask                                    # (3)
