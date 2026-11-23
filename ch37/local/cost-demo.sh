#!/usr/bin/env bash
# Sends the same load from curl to ratings in three data planes: sidecars
# in all five pods, ambient mode with ztunnel only, and ambient mode with
# a namespace waypoint. Reports latency and the CPU and memory of all
# proxies. You also need fortio and jq.
#
# Usage: sudo ch37/local/cost-demo.sh     (from the repository root)
set -euo pipefail
LAB=${LAB:-/tmp/ambient-lab}
PODS="curl productpage-v1 reviews-v1 reviews-v2 ratings-v1"
lab() { ambient-lab/lab.sh "$@"; }
trap 'lab down' EXIT

proxies() {                                   # PIDs of every running proxy
  pgrep -f "envoy-contrib -c $LAB/" || true
  pgrep -x ztunnel || true
}
cpu() {                                       # (1)
  for p in $(proxies); do awk '{print $14 + $15}' "/proc/$p/stat"; done |
    awk '{s += $1} END {print s}'
}
mem() {                                       # resident memory in MiB
  for p in $(proxies); do awk '/VmRSS/ {print $2}' "/proc/$p/status"; done |
    awk '{s += $1} END {printf "%d", s / 1024}'
}

run() {                                       # run TITLE
  local c0 n
  c0=$(cpu)
  echo "### $1"
  ip netns exec curl fortio load -quiet -qps 400 -c 8 -t 20s \
    -json "$LAB/fortio.json" http://10.96.10.12:9080/ratings/0 > /dev/null 2>&1
  jq -r '"\(.DurationHistogram.Count) requests, status "
         + (.RetCodes | keys | join(",")),
    (.DurationHistogram.Percentiles[] | select(.Percentile == 50 or
     .Percentile == 99)
     | "p\(.Percentile): \(.Value * 100000 | round / 100) ms")' \
    "$LAB/fortio.json"
  n=$(proxies | wc -l)
  awk -v c=$(( $(cpu) - c0 )) -v n="$n" -v m="$(mem)" 'BEGIN {
    printf "%d proxies: %.2f CPU seconds, %d MiB of memory\n", n, c / 100, m}'
}

lab up sidecar-all                                            # (2)
for pod in $PODS; do lab sidecar "$pod" start strict; done
lab ztunnel lab stop; lab ztunnel lab-m02 stop                # (3)
run "Sidecars in all five pods"

lab down
lab up
run "Ambient mode, ztunnel only"

lab config waypoint use-waypoint-namespace
lab waypoint waypoint start
run "Ambient mode with a namespace waypoint"
