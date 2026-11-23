#!/usr/bin/env bash
# Collects the evidence for a mesh escalation into one folder: versions,
# sync status, analyzer output, and for each pod its proxy's recent access
# log lines with response flags, its describe output and its routes and
# clusters. Attach the Kiali graph screenshot yourself.
#
# Usage: ch47/k8s/escalation-report.sh NAMESPACE POD [POD ...]
#        (KUBECTL=oc on OpenShift)
set -euo pipefail
K=${KUBECTL:-kubectl}
NS=${1:?usage: escalation-report.sh NAMESPACE POD [POD ...]}; shift
OUT=escalation-$(date -u +%Y%m%dT%H%M%SZ)
mkdir -p "$OUT"

{ istioctl version; $K version; } > "$OUT/versions.txt" 2>&1 || true
istioctl proxy-status -v 1 > "$OUT/proxy-status.txt" 2>&1 || true   # (1)
istioctl analyze -n "$NS" > "$OUT/analyze.txt" 2>&1 || true

for pod in "$@"; do
  d="$OUT/$pod"; mkdir -p "$d"
  $K logs -n "$NS" "$pod" -c istio-proxy --since=30m \
    > "$d/proxy.log" 2>&1 || true
  grep -E '" [0-9]{1,3} [A-Z]{2,}' "$d/proxy.log" | tail -50 \
    > "$d/flagged-requests.log" || true                         # (2)
  awk -F'"' '/" [45][0-9][0-9] /{print $10}' "$d/proxy.log" |
    sort -u | tail -20 > "$d/request-ids.txt" || true           # (3)
  istioctl x describe pod "$pod" -n "$NS" > "$d/describe.txt" 2>&1 || true
  istioctl proxy-config route "$pod" -n "$NS" > "$d/routes.txt" 2>&1 || true
  istioctl proxy-config cluster "$pod" -n "$NS" \
    > "$d/clusters.txt" 2>&1 || true
done

{
  echo "# Mesh escalation: namespace $NS, $(date -u)"
  echo; echo "## Proxies not SYNCED"
  grep -vE 'SYNCED.*SYNCED.*SYNCED.*SYNCED' "$OUT/proxy-status.txt" || true
  echo; echo "## Analyzer"
  cat "$OUT/analyze.txt"
  echo; echo "## Response flags in the last 30 minutes"
  cat "$OUT"/*/flagged-requests.log 2>/dev/null |
    awk '{print $5, $6, $7}' | sort | uniq -c | sort -rn      # (4)
} > "$OUT/SUMMARY.md"
tar czf "$OUT.tar.gz" "$OUT"
echo "wrote $OUT.tar.gz; add the Kiali graph and the trace IDs you checked"
