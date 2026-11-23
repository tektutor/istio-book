#!/usr/bin/env bash
# Benchmarks the same client and server with no mesh, with sidecars and in
# ambient mode. For each data plane and rate: a 10-second warm-up, then
# RUNS runs of 60 seconds. Prints one line per run: latency percentiles,
# proxy CPU per 1,000 requests and proxy memory, from Prometheus.
#
# Usage: ch45/k8s/bench.sh [rate ...]       (default: 200 800)
set -euo pipefail
RUNS=${RUNS:-3}; RATES=${*:-200 800}
kubectl port-forward -n istio-system svc/prometheus 9090:9090 \
  > /dev/null 2>&1 &
PF=$!; trap 'kill $PF' EXIT; sleep 2

prom() {                                      # prom QUERY -> one number
  curl -s --data-urlencode "query=$1" localhost:9090/api/v1/query |
    jq -r '.data.result[0].value[1] // "0"'
}
selector() {                                  # the proxies of a namespace
  case $1 in
    bench-sidecar) echo 'namespace="bench-sidecar",container="istio-proxy"' ;;
    bench-ambient) echo 'namespace="istio-system",pod=~"ztunnel-.*",'\
                        'container="istio-proxy"' ;;                # (1)
    *) echo 'namespace="none"' ;;
  esac
}
load() {                                      # load NS RATE SECONDS
  kubectl exec -n "$1" deploy/client -c client -- fortio load -quiet \
    -qps "$2" -c 4 -t "${3}s" -p "50,90,99" -json - \
    http://server:8080/echo 2> /dev/null                          # (2)
}

echo "plane rate run requests qps errors p50_ms p90_ms p99_ms" \
  "cpu_ms_per_1k mem_mib"
for ns in bench-nomesh bench-sidecar bench-ambient; do
  s=$(selector "$ns")
  for rate in $RATES; do
    load "$ns" "$rate" 10 > /dev/null
    for run in $(seq "$RUNS"); do
      json=$(load "$ns" "$rate" 60)
      sleep 20                                                  # (3)
      cpu=$(prom "sum(increase(
        container_cpu_usage_seconds_total{$s}[60s] offset 20s))")
      mem=$(prom "sum(max_over_time(
        container_memory_working_set_bytes{$s}[60s] offset 20s))")
      jq -r --arg p "${ns#bench-}" --arg r "$rate" --arg n "$run" \
        --arg cpu "$cpu" --arg mem "$mem" '
        .DurationHistogram as $h
        | [$h.Percentiles[] | .Value * 1000 | . * 100 | round / 100] as $pc
        | [$p, $r, $n, $h.Count, (.ActualQPS | floor),
           ([.RetCodes | to_entries[] | select(.key != "200") | .value]
            | add // 0), $pc[0], $pc[1], $pc[2],
           (($cpu | tonumber) * 1e6 / $h.Count | round),
           (($mem | tonumber) / 1048576 | round)]
        | map(tostring) | join(" ")' <<< "$json"
    done
  done
done
