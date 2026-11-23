#!/usr/bin/env bash
# Routing and policy at the waypoint of the local ambient lab: an
# HTTPRoute that matches a header, an AuthorizationPolicy with a
# targetRef, and a layer 4 policy that the waypoint breaks.
#
# Usage: sudo ch36/local/l7-demo.sh     (from the repository root)
set -euo pipefail
LAB=${LAB:-/tmp/ambient-lab}
lab() { ambient-lab/lab.sh "$@"; }
trap 'lab down' EXIT

get() {                                       # get POD URL: status and body
  local out
  out=$(ip netns exec "$1" curl -s -m 5 -w '\n%{http_code}' "http://$2")
  echo "$(tail -1 <<< "$out") $(head -n -1 <<< "$out")"
}
page() {                                      # what productpage got from reviews
  ip netns exec curl curl -s -m 5 http://10.96.10.10:9080/productpage |
    jq -c .reviews
}
versions() {                                  # versions [curl options]
  for _ in 1 2 3 4; do
    ip netns exec curl curl -s "$@" http://10.96.10.11:9080/reviews/0 |
      python3 -c 'import json, sys; print(json.load(sys.stdin)["version"])'
  done | sort | uniq -c | awk '{printf "%s x%s  ", $2, $1} END {print ""}'
}

lab up waypoint use-waypoint-reviews
lab waypoint waypoint start
echo "### 1. No HTTPRoute: reviews-v1 and reviews-v2 take turns"
versions

lab routes waypoint reviews-header.yaml                        # (1)
echo "### 2. HTTPRoute with a header match"
echo "end-user: melissa -> $(versions -H 'end-user: melissa')"
echo "end-user: michail -> $(versions -H 'end-user: michail')"

lab routes waypoint reviews-authz.yaml
echo "### 3. AuthorizationPolicy for the Service reviews"
echo "curl -> reviews:           $(get curl 10.96.10.11:9080/reviews/0)"
echo "productpage -> reviews:    $(page)"
sleep 0.5
grep '"GET /reviews' "$LAB/waypoint/access.log" | tail -2 |
  awk '{print $5, $6, $7, $NF}'

lab routes waypoint routes/reviews.yaml
lab config waypoint use-waypoint-reviews reviews-l4-policy      # (2)
echo "### 4. A layer 4 policy on the reviews pods: productpage only"
mark=$(date +%s.%N)
echo "productpage -> reviews:    $(page)"
sleep 1
python3 ambient-lab/hops.py "$mark" "$LAB"

lab config waypoint use-waypoint-reviews reviews-l4-policy \
  reviews-l4-policy-waypoint
echo "### 5. The same policy with the waypoint's identity added"
echo "productpage -> reviews:    $(page)"
