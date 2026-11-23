#!/usr/bin/env bash
# Benchmarks the path from curl to ratings in the local ambient lab in four
# data planes: no mesh, sidecars, ambient with ztunnel only, and ambient
# with a waypoint. For each plane and request rate it runs a warm-up, then
# RUNS measured runs, and prints one line per run: latency percentiles,
# the CPU the proxies used per 1,000 requests, and their memory.
#
# Usage: sudo ch45/local/bench.sh [rate ...]     (default: 200 800)
# Needs: the ambient lab, fortio and jq. RUNS and SECONDS_PER_RUN override
# the defaults of 3 runs of 30 seconds.
set -euo pipefail
LAB=${LAB:-/tmp/ambient-lab}
RUNS=${RUNS:-3}; SECS=${SECONDS_PER_RUN:-30}
RATES=${*:-200 800}
URL=http://10.96.10.12:9080/ratings/0                           # (1)
lab() { ambient-lab/lab.sh "$@" > /dev/null; }
trap 'lab down' EXIT

proxies() {                                   # PIDs of the proxies in use
  case $1 in
    nomesh) ;;
    sidecar) pgrep -f "envoy-contrib -c $LAB/(curl|ratings-v1)/" ;;
    ambient) pgrep -x ztunnel ;;
    waypoint) pgrep -x ztunnel; pgrep -f "envoy-contrib -c $LAB/waypoint/" ;;
  esac
}
ticks() {                                     # CPU time in 1/100 s  # (2)
  local s=0
  for p in $(proxies "$1"); do
    s=$((s + $(awk '{print $14 + $15}' "/proc/$p/stat")))
  done; echo $s
}
rss() {                                       # resident memory in MiB
  local s=0
  for p in $(proxies "$1"); do
    s=$((s + $(awk '/VmRSS/ {print $2}' "/proc/$p/status")))
  done; echo $((s / 1024))
}
load() {                                      # load RATE SECONDS
  ip netns exec curl fortio load -quiet -qps "$1" -c 4 -t "${2}s" \
    -p "50,90,99" -json "$LAB/fortio.json" "$URL" > /dev/null 2>&1
}

setup() {                                     # (3)
  case $1 in
    nomesh) lab up; lab unenroll curl; lab unenroll ratings-v1 ;;
    sidecar) lab up sidecar-curl sidecar-ratings
             lab sidecar curl start strict
             lab sidecar ratings-v1 start strict
             lab ztunnel lab stop; lab ztunnel lab-m02 stop ;;
    ambient) lab up ;;
    waypoint) lab up waypoint use-waypoint-namespace
              lab waypoint waypoint start ;;
  esac
}

echo "plane rate run requests qps errors p50_ms p90_ms p99_ms" \
  "cpu_ms_per_1k rss_mib"
for plane in ${PLANES:-nomesh sidecar ambient waypoint}; do
  setup "$plane"
  for rate in $RATES; do
    load "$rate" 10                                             # (4)
    for run in $(seq "$RUNS"); do
      t0=$(ticks "$plane")
      load "$rate" "$SECS"
      t1=$(ticks "$plane")
      jq -r --arg p "$plane" --arg r "$rate" --arg n "$run" \
        --argjson cpu $(( (t1 - t0) * 10 )) --argjson rss "$(rss "$plane")" '
        .DurationHistogram as $h
        | [$h.Percentiles[] | .Value * 1000 | . * 100 | round / 100] as $pc
        | [$p, $r, $n, $h.Count, (.ActualQPS | floor),
           ([.RetCodes | to_entries[] | select(.key != "200") | .value]
            | add // 0),
           $pc[0], $pc[1], $pc[2],
           ($cpu * 1000 / $h.Count | . * 10 | round / 10), $rss]
        | map(tostring) | join(" ")' "$LAB/fortio.json"          # (5)
    done
  done
  lab down
done
