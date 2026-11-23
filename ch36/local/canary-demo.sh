#!/usr/bin/env bash
# Shifts the Service reviews from the waypoint waypoint to waypoint-v2 in
# steps, with Istio 1.31's canary weight, and counts where ztunnel sent
# 200 new connections at each step. Then sends 20 requests over one
# connection, which all take the same waypoint.
#
# Usage: sudo ch36/local/canary-demo.sh     (from the repository root)
set -euo pipefail
LAB=${LAB:-/tmp/ambient-lab}
lab() { ambient-lab/lab.sh "$@"; }
trap 'lab down' EXIT

count() {                                     # count: where 200 connections went
  local mark
  mark=$(date +%s.%N)
  for _ in $(seq 200); do                     # (1)
    ip netns exec curl curl -s -o /dev/null http://10.96.10.11:9080/headers
  done
  sleep 1
  python3 ambient-lab/hops.py "$mark" "$LAB" |
    awk '{print $5}' | sort | uniq -c
}

lab up waypoint waypoint-v2 use-waypoint-reviews
lab waypoint waypoint start
lab waypoint waypoint-v2 start
for step in canary-10 canary-50; do
  lab config waypoint waypoint-v2 "$step"
  echo "### Canary weight ${step#canary-}"
  jq -c '.services[] | select(.name == "reviews") | .weightedWaypoints[]
         | [.destination.destination, .weight]' "$(lab dump lab)"     # (2)
  count
done

served() {                                    # served WAYPOINT: requests so far
  ip netns exec "$1" curl -s localhost:15000/stats |
    awk -F': ' '$1 == "http.reviews.downstream_rq_completed" {print $2}'
}
echo "### 20 requests over one connection"                   # (3)
before1=$(served waypoint); before2=$(served waypoint-v2)
urls=$(for _ in $(seq 20); do echo http://10.96.10.11:9080/headers; done)
ip netns exec curl curl -s $urls > /dev/null
echo "waypoint:    $(( $(served waypoint) - before1 )) requests"
echo "waypoint-v2: $(( $(served waypoint-v2) - before2 )) requests"
