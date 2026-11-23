#!/usr/bin/env bash
# Moves a sidecar-era policy with HTTP rules to ambient mode: first as it
# is, with a selector, then as a waypoint policy with targetRefs.
#
# Usage: sudo ch37/local/policy-demo.sh     (from the repository root)
set -euo pipefail
LAB=${LAB:-/tmp/ambient-lab}
lab() { ambient-lab/lab.sh "$@"; }
trap 'lab down' EXIT

page() {                                      # what productpage got from reviews
  ip netns exec curl curl -s -m 5 http://10.96.10.10:9080/productpage |
    jq -c .reviews
}
code() {                                      # curl's own call to reviews
  ip netns exec curl curl -s -m 5 -o /dev/null -w '%{http_code}' \
    http://10.96.10.11:9080/reviews/0
}

lab up reviews-get-only-ztunnel                                # (1)
echo "### 1. The selector policy, enforced by ztunnel"
mark=$(date +%s.%N)
echo "productpage -> reviews: $(page)"
echo "curl -> reviews:        $(code)"
sleep 1
python3 ambient-lab/hops.py "$mark" "$LAB" | grep -A1 'reviews' | head -2

lab config reviews-deny-admin-ztunnel
echo "### 2. A DENY policy for /admin/* on port 9080, enforced by ztunnel"
mark=$(date +%s.%N)
echo "productpage -> reviews: $(page)"
sleep 1
python3 ambient-lab/hops.py "$mark" "$LAB" | grep -A1 'reviews' | head -2

lab config waypoint use-waypoint-reviews                       # (2)
lab waypoint waypoint start
lab routes waypoint reviews-authz.yaml
echo "### 3. The ALLOW rule with targetRefs, at the waypoint"
echo "productpage -> reviews: $(page)"
echo "curl -> reviews:        $(code)"
