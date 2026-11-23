#!/usr/bin/env bash
# Measures config propagation time: from the moment the API server has
# stored a change to the moment one sidecar has applied it. The change is
# an AuthorizationPolicy for the pods with label app=APP; the sidecar's
# Envoy records when it last accepted new listeners. TRIALS changes, two
# seconds apart, then the minimum, median, 90th percentile and maximum.
#
# Usage: ch45/k8s/prop-time.sh NAMESPACE APP [TRIALS]   (default 20)
#        KUBECTL=oc ch45/k8s/prop-time.sh shop orders   (OpenShift)
set -euo pipefail
NS=$1 APP=$2 TRIALS=${3:-20}
K=${KUBECTL:-kubectl}
POD=$($K get pod -n "$NS" -l app="$APP" \
  -o jsonpath='{.items[0].metadata.name}')
lds() {                                       # last listener update, ms
  $K exec -n "$NS" "$POD" -c istio-proxy -- \
    pilot-agent request GET 'stats?filter=lds.update_time' |
    awk -F': ' '/update_time/ {print $2}'
}
# On OpenShift Local, the VM's clock can drift from your machine's. The
# proxy image there has `date`, so measure the offset once and correct it.
OFF=0
if [[ $K == oc ]]; then                       # the quickest of five reads
  best=999999
  for _ in 1 2 3 4 5; do
    t0=$(date +%s%3N)
    pod=$($K exec -n "$NS" "$POD" -c istio-proxy -- date +%s%3N)
    t1=$(date +%s%3N)
    (( t1 - t0 < best )) && { best=$((t1 - t0)); OFF=$((pod - (t0 + t1) / 2)); }
  done
  echo "node clock offset: $OFF ms (read in $best ms)"
fi
policy() {                                    # policy TRIAL
  cat <<Y
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata: {name: propagation-probe, namespace: $NS}
spec:
  selector: {matchLabels: {app: $APP}}
  action: DENY
  rules: [{to: [{operation: {paths: ["/propagation-probe-$1"]}}]}]
Y
}
results=()
for i in $(seq "$TRIALS"); do
  before=$(lds)
  policy "$i" | $K apply -f - > /dev/null
  stored=$(( $(date +%s%3N) + OFF ))                            # (1)
  for _ in $(seq 100); do
    now=$(lds); [[ $now != "$before" ]] && break; sleep 0.1
  done
  if [[ $now == "$before" ]]; then                              # (2)
    echo "trial $i: no update within 10 s, skipped"
  else
    results+=($((now - stored)))
    echo "trial $i: $((now - stored)) ms"
  fi
  sleep 2
done
policy 0 | $K delete -f - > /dev/null
printf '%s\n' "${results[@]}" | sort -n | awk '{v[NR] = $1}
  END {printf "min %d ms, median %d ms, p90 %d ms, max %d ms\n",
       v[1], v[int((NR + 1) / 2)], v[int(NR * 0.9)], v[NR]}'   # (3)
