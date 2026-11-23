#!/usr/bin/env bash
# Builds a "pod" network namespace with the sidecar capture rules, a
# stand-in sidecar (Envoy as user 1337) and an application (user 1000),
# then sends one inbound and two outbound connections and shows where
# each one went. Needs Linux, root, iptables, python3 and an envoy binary.
#
# Usage: sudo ENVOY=/path/to/envoy ch11/local/capture-demo.sh
set -euo pipefail

ENVOY=${ENVOY:-envoy}
DIR=$(cd "$(dirname "$0")" && pwd)
LOG=$(mktemp -d)

cleanup() {                                   # (1)
  pkill -f "^$ENVOY -c $DIR/envoy-capture.yaml" 2>/dev/null || true
  pkill -f "^python3 -m http.server 80[89]0" 2>/dev/null || true
  for ns in pod client server; do ip netns del "$ns" 2>/dev/null || true; done
  ip link del cap0 2>/dev/null || true
}
trap cleanup EXIT
cleanup

# A bridge with three namespaces: pod .2, client .3, server .4.  # (2)
ip link add cap0 type bridge
ip addr add 10.88.0.1/24 dev cap0
ip link set cap0 up
for pair in pod:2 client:3 server:4; do
  ns=${pair%%:*}
  ip netns add "$ns"
  ip link add "v-$ns" type veth peer name eth0 netns "$ns"
  ip link set "v-$ns" master cap0 up
  ip netns exec "$ns" ip addr add "10.88.0.${pair##*:}/24" dev eth0
  ip netns exec "$ns" ip link set eth0 up
  ip netns exec "$ns" ip link set lo up
done
iptables -C FORWARD -i cap0 -o cap0 -j ACCEPT 2>/dev/null ||
  iptables -I FORWARD -i cap0 -o cap0 -j ACCEPT

# What istio-init does: load the capture rules into the pod.  # (3)
ip netns exec pod iptables-restore < "$DIR/sidecar-rules.v4"

# The sidecar runs as user 1337, the application as user 1000.  # (4)
ip netns exec pod setpriv --reuid 1337 --regid 1337 --clear-groups \
  "$ENVOY" -c "$DIR/envoy-capture.yaml" --base-id 11 \
  --file-flush-interval-msec 500 --log-level error > "$LOG/envoy.log" 2>&1 &
ip netns exec pod setpriv --reuid 1000 --regid 1000 --clear-groups \
  python3 -m http.server 8080 --directory /tmp > /dev/null 2>&1 &
ip netns exec server python3 -m http.server 8090 --directory /tmp \
  > /dev/null 2>&1 &
sleep 3

# get USER URL: request URL from inside the pod as USER, print the status
get() {
  ip netns exec pod setpriv --reuid "$1" --regid "$1" --clear-groups \
    curl -s -o /dev/null -w "%{http_code}\n" "$2"
}

echo "1. client -> pod:8080 (inbound)"
ip netns exec client curl -s -o /dev/null -w "%{http_code}\n" \
  http://10.88.0.2:8080/
echo "2. application in the pod -> server:8090 (outbound)"
get 1000 http://10.88.0.4:8090/
echo "3. user 1337 in the pod -> server:8090 (not captured)"
get 1337 http://10.88.0.4:8090/
sleep 3

echo; echo "Envoy access log:"
cat "$LOG/envoy.log"
echo; echo "Rule counters in the pod, [packets:bytes]:"     # (5)
ip netns exec pod iptables-save -c -t nat | grep -- "-A "
