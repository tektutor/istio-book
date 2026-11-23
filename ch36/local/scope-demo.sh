#!/usr/bin/env bash
# Sends three calls through the local ambient lab, first with a waypoint
# for the Service reviews only, then with a waypoint for the namespace,
# and shows where ztunnel sent each call and what the waypoint saw.
#
# Usage: sudo ch36/local/scope-demo.sh     (from the repository root)
set -euo pipefail
LAB=${LAB:-/tmp/ambient-lab}
lab() { ambient-lab/lab.sh "$@"; }
trap 'lab down' EXIT

calls() {                                     # (1)
  local mark seen
  mark=$(date +%s.%N)
  seen=$(grep -c . "$LAB/waypoint/access.log" || true)
  for url in 10.96.10.11:9080/headers 10.96.10.12:9080/headers \
             10.244.1.11:9080/headers; do
    printf "%-26s %s\n" "$url" "$(ip netns exec curl curl -s -o /dev/null \
      -w '%{http_code}' "http://$url")"
  done
  sleep 1
  echo "--- ztunnel"
  python3 ambient-lab/hops.py "$mark" "$LAB"
  echo "--- waypoint"
  tail -n +"$((seen + 1))" "$LAB/waypoint/access.log" | grep '"GET' |
    awk '{print $5, $6, $9, $10}'                               # (2)
}

lab up waypoint use-waypoint-reviews
lab waypoint waypoint start
echo "### 1. A waypoint for the Service reviews"
istioctl ztunnel-config services --file "$(lab dump lab)"
calls

lab config waypoint use-waypoint-namespace
echo "### 2. A waypoint for the namespace bookinfo"
istioctl ztunnel-config services --file "$(lab dump lab)"
calls
