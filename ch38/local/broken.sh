#!/usr/bin/env bash
# Breaks the local ambient lab in one of five ways, shows the symptom,
# runs the checks that find the cause, and repairs it.
#
#   not-enrolled   the client pod is not in ambient mode, the mesh is STRICT
#   hbone-blocked  a network policy drops port 15008 to one reviews pod
#   no-waypoint    a typo in the use-waypoint label
#   waypoint-down  the waypoint has no ready pod
#   ztunnel-down   the ztunnel of the node lab is not running
#
# Usage: sudo ch38/local/broken.sh SCENARIO     (from the repository root)
set -euo pipefail
LAB=${LAB:-/tmp/ambient-lab}
lab() { ambient-lab/lab.sh "$@"; }
trap 'lab down' EXIT

call() {                                      # call POD URL: status and time
  ip netns exec "$1" curl -s -m 15 -o /dev/null \
    -w "$1 -> $2: %{http_code} after %{time_total}s\n" "http://$2" || true
}
hops() { sleep 1; python3 ambient-lab/hops.py "$1" "$LAB"; }
failed() {                                    # failed NODE: ztunnel's counters
  ip netns exec "ztunnel-$1" curl -s localhost:15020/metrics |
    grep '^istio_tcp_connections_failed_total' | sed -E \
    's/.*reporter="([a-z]+)".*destination_workload="([^"]+)".*'\
'response_flags="([A-Z_]+)".* ([0-9]+)$/\1 \2 \3 \4/'
}

case ${1:-} in
not-enrolled)                                                   # (1)
  lab up strict curl-not-ambient
  lab unenroll curl
  echo "### Symptom"; m=$(date +%s.%N)
  call curl 10.96.10.11:9080/reviews/0
  echo "### ztunnel's log"; hops "$m"
  echo "### ztunnel's view of the client"
  istioctl ztunnel-config workloads --file "$(lab dump lab)" |
    grep -E 'NAME|curl'
  jq -r '.workloadState | keys | join(" ")' "$LAB/lab/config_dump.json"
  echo "### Repair: enroll the pod"
  lab config strict; lab enroll curl; sleep 1
  call curl 10.96.10.11:9080/reviews/0 ;;
hbone-blocked)                                                  # (2)
  lab up strict
  ip netns exec ambient-net iptables -A FORWARD -d 10.244.2.11 \
    -p tcp --dport 15008 -j DROP
  echo "### Symptom"; m=$(date +%s.%N)
  for _ in 1 2; do call curl 10.96.10.14:9080/reviews/0; done
  echo "### ztunnel's log"; hops "$m"
  echo "### ztunnel's metrics on the node lab"; failed lab
  echo "### Repair: allow port 15008"
  ip netns exec ambient-net iptables -F FORWARD
  call curl 10.96.10.14:9080/reviews/0 ;;
no-waypoint)                                                    # (3)
  lab up strict waypoint use-waypoint-typo
  lab waypoint waypoint start
  lab routes waypoint reviews-authz.yaml
  echo "### Symptom: the policy allows only productpage"
  m=$(date +%s.%N)
  call curl 10.96.10.11:9080/reviews/0
  echo "### ztunnel's view of the Service"
  istioctl ztunnel-config services --file "$(lab dump lab)" |
    grep -E 'NAME|reviews '
  hops "$m"
  echo "### Repair: the right label"
  lab config strict waypoint use-waypoint-reviews
  call curl 10.96.10.11:9080/reviews/0 ;;
waypoint-down)                                                  # (4)
  lab up strict waypoint use-waypoint-reviews waypoint-down
  echo "### Symptom"; m=$(date +%s.%N)
  call curl 10.96.10.11:9080/reviews/0
  call curl 10.96.10.12:9080/ratings/0
  echo "### ztunnel's log"; hops "$m"
  echo "### Repair: a ready waypoint"
  lab config strict waypoint use-waypoint-reviews
  lab waypoint waypoint start
  call curl 10.96.10.11:9080/reviews/0 ;;
ztunnel-down)                                                   # (5)
  lab up strict
  lab ztunnel lab stop
  echo "### Symptom"; m=$(date +%s.%N)
  call curl 10.96.10.12:9080/ratings/0
  call ratings-v1 10.244.1.11:9080/reviews/0
  echo "### ztunnel's log on the node lab-m02"; hops "$m"
  echo "### The pods' sockets on the node lab"
  ip netns exec curl ss -ltn | grep -E 'State|1500[168]' || echo "none"
  echo "### Repair: start ztunnel; the node agent hands it the pods again"
  lab ztunnel lab start
  ip netns exec curl ss -ltn | grep -E 'State|1500[168]'
  call curl 10.96.10.12:9080/ratings/0 ;;
*) sed -n '2,10p' "$0"; exit 2 ;;
esac
