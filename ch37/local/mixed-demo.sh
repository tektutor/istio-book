#!/usr/bin/env bash
# Sidecars and ambient pods in one mesh: a sidecar client skips the
# waypoint and its policy, a sidecar server gets HBONE from ztunnel, and
# a sidecar injected before ambient mode was installed gets plain TCP.
#
# Usage: sudo ch37/local/mixed-demo.sh     (from the repository root)
set -euo pipefail
LAB=${LAB:-/tmp/ambient-lab}
lab() { ambient-lab/lab.sh "$@"; }
trap 'lab down' EXIT

get() {                                       # get URL: status and body
  local out
  out=$(ip netns exec curl curl -s -m 5 -w '\n%{http_code}' "http://$1" ||
        true)
  echo "$(tail -1 <<< "$out") $(head -n -1 <<< "$out")"
}
connections() {                               # open connections on a node
  istioctl ztunnel-config connections --file "$(lab dump "$1")" | tail -n +2
}

lab up waypoint use-waypoint-reviews
lab waypoint waypoint start
lab routes waypoint reviews-authz.yaml                         # (1)
echo "### 1. Ambient curl -> reviews, through the waypoint"
echo "curl -> reviews: $(get 10.96.10.11:9080/reviews/0)"

lab config waypoint use-waypoint-reviews sidecar-curl
lab sidecar curl start strict                                  # (2)
echo "### 2. curl with a sidecar -> reviews"
echo "curl -> reviews: $(get 10.96.10.11:9080/reviews/0)"
grep -c '"GET /reviews' "$LAB/waypoint/access.log" |
  sed 's/^/requests in the waypoint log: /'
connections lab; connections lab-m02

lab sidecar curl stop
lab down
lab up old-sidecar-ratings
lab sidecar ratings-v1 start strict                            # (3)
echo "### 3. Ambient curl -> ratings with an old sidecar, STRICT"
mark=$(date +%s.%N)
echo "curl -> ratings: $(get 10.96.10.12:9080/ratings/0)"
sleep 1
python3 ambient-lab/hops.py "$mark" "$LAB"
grep -m1 ' NR ' "$LAB/ratings-v1/access.log" || true
lab sidecar ratings-v1 start permissive
echo "### 4. The same sidecar, PERMISSIVE"
echo "curl -> ratings: $(get 10.96.10.12:9080/ratings/0)"
sleep 0.5
grep '"GET /ratings' "$LAB/ratings-v1/access.log" | tail -1 |
  awk '{print $5, $(NF-1), $NF}'

lab config sidecar-ratings
lab sidecar ratings-v1 start strict                            # (4)
echo "### 5. A sidecar with the tunnel label, STRICT"
echo "curl -> ratings: $(get 10.96.10.12:9080/ratings/0)"
sleep 0.5
grep '"GET /ratings' "$LAB/ratings-v1/access.log" | tail -1 |
  awk '{print $5, $(NF-1), $NF}'
