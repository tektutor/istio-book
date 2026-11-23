#!/usr/bin/env bash
# Sends the same load to ratings without a waypoint and through one, and
# reports latency from Fortio and the CPU and memory of the waypoint and
# of the two ztunnels. You also need fortio.
#
# Usage: sudo ch36/local/load-demo.sh     (from the repository root)
set -euo pipefail
LAB=${LAB:-/tmp/ambient-lab}
lab() { ambient-lab/lab.sh "$@"; }
trap 'lab down' EXIT

cpu() { awk '{print $14 + $15}' "/proc/$1/stat"; }             # (1)
rss() { awk '/VmRSS/ {print int($2 / 1024)}' "/proc/$1/status"; }

run() {                                       # run TITLE
  local wp z1 z2 c0 c1 c2
  wp=$(pgrep -f "envoy-contrib -c $LAB/waypoint/envoy.yaml")
  z1=$(cat "$LAB/lab/ztunnel.pid"); z2=$(cat "$LAB/lab-m02/ztunnel.pid")
  c0=$(cpu "$wp"); c1=$(cpu "$z1"); c2=$(cpu "$z2")
  echo "### $1"
  ip netns exec curl fortio load -quiet -qps 400 -c 8 -t 20s \
    -json "$LAB/fortio.json" http://10.96.10.12:9080/ratings/0 > /dev/null 2>&1
  jq -r '"\(.DurationHistogram.Count) requests, "
    + "\(.ActualQPS | floor) per second, status \(.RetCodes | keys | join(","))",
    (.DurationHistogram.Percentiles[] | select(.Percentile >= 50)
     | "p\(.Percentile): \(.Value * 1000 | . * 100 | round / 100) ms")' \
    "$LAB/fortio.json"                                          # (2)
  awk -v a=$(( $(cpu "$wp") - c0 )) -v b=$(( $(cpu "$z1") - c1 )) \
      -v c=$(( $(cpu "$z2") - c2 )) 'BEGIN {printf "CPU seconds: waypoint" \
      " %.2f, ztunnel lab %.2f, ztunnel lab-m02 %.2f\n", a/100, b/100, c/100}' 
  echo "Memory (MiB): waypoint $(rss "$wp"), ztunnel lab $(rss "$z1")," \
       "ztunnel lab-m02 $(rss "$z2")"
}

lab up waypoint use-waypoint-reviews
lab waypoint waypoint start
run "ratings without a waypoint"
lab config waypoint use-waypoint-namespace
run "ratings through the namespace waypoint"
