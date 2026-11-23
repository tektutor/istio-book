#!/usr/bin/env bash
# Measures the sidecar of one pod of the echo service under a fixed load:
# what the kernel counts for the proxy container (CPU, memory, throttling)
# and what Envoy sees (worker threads, clusters, allocated memory). Run it
# before and after each change in Lab 45.3, at the same rate, and compare
# the lines.
#
# Usage: ch45/k8s/proxy-usage.sh RATE [SECONDS]   (default: 60 seconds)
#        KUBECTL=oc ch45/k8s/proxy-usage.sh RATE   (OpenShift)
set -euo pipefail
RATE=$1; SECS=${2:-60}; NS=sizing
kubectl() { command ${KUBECTL:-kubectl} "$@"; }
POD=$(kubectl get pod -n $NS -l app=echo --field-selector=status.phase=Running \
  -o jsonpath='{.items[0].metadata.name}')
P='{.spec.nodeName} '
P+='{.status.initContainerStatuses[?(@.name=="istio-proxy")].containerID}'
read -r NODE CID < <(kubectl get pod -n $NS "$POD" -o jsonpath="$P"; echo)
if [[ ${KUBECTL:-kubectl} == oc ]]; then      # the UBI proxy image has cat
  cg() { kubectl exec -n $NS "$POD" -c istio-proxy -- cat "/sys/fs/cgroup/$1"; }
else
  CG=$(docker exec "$NODE" find /sys/fs/cgroup/kubepods.slice -maxdepth 3 \
    -type d -name "docker-${CID#docker://}.scope")                 # (1)
  [ -n "$CG" ] || { echo "no cgroup for $POD on node $NODE"; exit 1; }
  cg() { docker exec "$NODE" cat "$CG/$1"; }  # cg FILE -> the cgroup file
fi
cpustat() {                           # usage_usec nr_periods nr_throttled
  cg cpu.stat | awk '$1 == "usage_usec" || $1 == "nr_periods" ||
                     $1 == "nr_throttled" {printf "%s ", $2}
                     END {print ""}'
}
wset() {                                      # working set in MiB
  cg memory.stat | awk -v cur="$(cg memory.current)" \
    '$1 == "inactive_file" {print int((cur - $2) / 1048576)}'
}                                                                  # (3)

read -r u0 p0 t0 < <(cpustat)
kubectl exec -n $NS deploy/load -c load -- fortio load -quiet \
  -qps "$RATE" -c 4 -t "${SECS}s" -json - http://echo:8080/echo \
  > /tmp/fortio-$$.json 2> /tmp/fortio-$$.err &                   # (2)
LOAD=$!
mem=0
while kill -0 $LOAD 2> /dev/null; do          # sample memory every 5 seconds
  m=$(wset); if (( m > mem )); then mem=$m; fi
  sleep 5
done
wait $LOAD || { echo "fortio failed:"; cat /tmp/fortio-$$.err; exit 1; }
read -r u1 p1 t1 < <(cpustat)
p99=$(jq '.DurationHistogram.Percentiles[] | select(.Percentile == 99)
      | .Value * 1000 | . * 100 | round / 100' /tmp/fortio-$$.json)
rm -f /tmp/fortio-$$.json /tmp/fortio-$$.err

cpu=$(( (u1 - u0) / (SECS * 1000) ))          # microseconds per second / 1000
thr=$(awk -v t=$(( ${t1:-0} - ${t0:-0} )) -v p=$(( ${p1:-0} - ${p0:-0} )) \
  'BEGIN {printf "%.1f", (p > 0 ? t * 100 / p : 0)}')             # (4)

agent() {                                     # agent PATH -> Envoy admin
  kubectl exec -n $NS "$POD" -c istio-proxy -- pilot-agent request GET "$1"
}
workers=$(agent server_info |
  jq -r '.command_line_options.concurrency')                      # (5)
heap=$(agent memory |
  jq -r '(.allocated | tonumber) / 1048576 | round')              # (6)
clusters=$(istioctl proxy-config clusters "$POD" -n $NS | tail -n +2 | wc -l)

printf 'rate=%s p99_ms=%s cpu_m=%s mem_mib=%s throttled_pct=%s\n' \
  "$RATE" "$p99" "$cpu" "$mem" "$thr"
printf 'workers=%s clusters=%s envoy_allocated_mib=%s\n' \
  "$workers" "$clusters" "$heap"
