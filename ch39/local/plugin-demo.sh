#!/usr/bin/env bash
# Runs one Envoy with the tenant check as a Rust or Go Wasm module, or as
# a Lua script, and sends three requests. "load" sends the same load to
# Envoy without a filter and with each version, and reports latency, CPU
# and memory. You need envoy-contrib, curl, and fortio and jq for "load".
#
# Usage: ch39/local/plugin-demo.sh rust|go|lua|load  (from the repository
#        root, after building the modules with tenant-*/build.sh)
set -euo pipefail
CODE=$(cd "$(dirname "$0")/.." && pwd)
OUT=${OUT:-/tmp/ch39-demo}
ENVOY=${ENVOY:-envoy-contrib}
mkdir -p "$OUT"
PID=
trap '[[ -n $PID ]] && kill $PID 2>/dev/null; true' EXIT

start() {                                     # start rust|go|lua|none
  local filter=$CODE/local/filters/wasm.yaml module
  case $1 in                                  # (1)
    rust) module=$CODE/tenant-rust/target/wasm32-unknown-unknown/release
          module=$module/tenant_check.wasm ;;
    go)   module=$CODE/tenant-go/tenant_check.wasm ;;
    lua)  module=$CODE/lua/tenant-check.lua
          filter=$CODE/local/filters/lua.yaml ;;
    none) module=; filter=/dev/null ;;
  esac
  sed "s|MODULE|$module|" "$filter" > "$OUT/filter.yaml"
  sed "/^#FILTER/{r $OUT/filter.yaml
d}" "$CODE/local/envoy-base.yaml" > "$OUT/envoy.yaml"   # (2)
  "$ENVOY" -c "$OUT/envoy.yaml" --concurrency 2 --log-level warn \
    > "$OUT/envoy.log" 2>&1 &
  PID=$!
  until curl -s localhost:18601/ready | grep -q LIVE; do
    kill -0 $PID 2>/dev/null || { grep -m3 -E 'error|critical' \
      "$OUT/envoy.log"; exit 1; }
    sleep 0.2
  done
}

stop() { kill $PID; wait $PID 2>/dev/null || true; PID=; }

ask() {                                       # ask LABEL [curl options]
  local label=$1 code stamp; shift
  code=$(curl -s -D "$OUT/headers" -o "$OUT/body" -w '%{http_code}' "$@" \
    http://127.0.0.1:18600/)
  stamp=$(grep -i '^x-tenant-checked' "$OUT/headers" | tr -d '\r' || true)
  printf '%-16s %s %s%s\n' "$label" "$code" "$(cat "$OUT/body")" \
    "${stamp:+   ($stamp)}"
}

cpu() { awk '{print $14 + $15}' "/proc/$1/stat"; }
rss() { awk '/VmRSS/ {print int($2 / 1024)}' "/proc/$1/status"; }

load() {                                      # load rust|go|lua|none
  local c0 n codes p50 p99
  start "$1"
  c0=$(cpu $PID)
  fortio load -quiet -qps 2000 -c 8 -t 15s -H 'x-tenant: acme' \
    -json "$OUT/fortio.json" http://127.0.0.1:18600/ > /dev/null 2>&1  # (3)
  read -r n codes p50 p99 < <(jq -r '[.DurationHistogram.Count,
    (.RetCodes | keys | join(",")), (.DurationHistogram.Percentiles[]
    | select(.Percentile == 50 or .Percentile == 99)
    | .Value * 1e6 | round)] | map(tostring) | join(" ")' "$OUT/fortio.json")
  printf '%-6s %8s %6s %7s %7s %6.2f %7s\n' "$1" "$n" "$codes" "$p50" \
    "$p99" "$(( $(cpu $PID) - c0 ))e-2" "$(rss $PID)"
  stop
}

case ${1:-} in
  rust|go|lua)
    start "$1"
    ask "no header"
    ask "x-tenant: acme" -H 'x-tenant: acme'
    ask "x-tenant: evil" -H 'x-tenant: evil'
    curl -s localhost:18601/stats | grep '^wasmcustom' || true   # (4)
    ;;
  load)
    echo "filter requests status p50(us) p99(us) CPU(s) RSS(MiB)"
    for f in none lua rust go; do load "$f"; done
    ;;
  *) sed -n '2,9p' "$0"; exit 2 ;;
esac
