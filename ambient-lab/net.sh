#!/usr/bin/env bash
# Builds the network of the local ambient lab, or removes it.
#
# A namespace called ambient-net plays the cluster network and the two
# nodes, lab and lab-m02: every pod is a network namespace with one
# address, connected to ambient-net by a veth pair, as many CNI plugins
# do it. ambient-net also plays kube-proxy for the Service addresses.
#
# Usage: ambient-lab/net.sh up|down     (as root)
set -euo pipefail
DIR=$(cd "$(dirname "$0")" && pwd)
NET=ambient-net
in_net() { ip netns exec $NET "$@"; }

pods() { grep -v '^#' "$DIR/pods.txt" | awk 'NF {print $1, $4}'; }

down() {
  for p in $(pods | cut -d' ' -f1) ztunnel-lab ztunnel-lab-m02 $NET; do
    ip netns del "$p" 2>/dev/null || true
  done
}

up() {
  down
  ip netns add $NET
  in_net ip link set lo up
  in_net sysctl -qw net.ipv4.ip_forward=1
  # Every pod's default gateway. ambient-net owns the address, so it
  # answers the pods' ARP requests for it.                       # (1)
  in_net ip addr add 169.254.1.1/32 dev lo
  i=0
  while read -r pod ip; do
    i=$((i + 1))
    ip netns add "$pod"
    ip link add "v$i" netns $NET type veth peer name eth0 netns "$pod"
    in_net ip link set "v$i" up
    in_net ip route add "$ip/32" dev "v$i"
    ip -n "$pod" link set lo up
    ip -n "$pod" link set eth0 up
    ip -n "$pod" addr add "$ip/32" dev eth0
    ip -n "$pod" route add 169.254.1.1 dev eth0
    ip -n "$pod" route add default via 169.254.1.1 dev eth0
  done < <(pods)
  # The ztunnel pods of the two nodes. They need no network of their
  # own: ztunnel opens its sockets inside each pod's namespace.  # (2)
  for n in lab lab-m02; do
    ip netns add "ztunnel-$n"
    ip -n "ztunnel-$n" link set lo up
  done
  kube_proxy
}

# kube-proxy: send each Service address to the pods behind it.   # (3)
kube_proxy() {
  in_net iptables -t nat -F PREROUTING
  in_net iptables -t nat -A PREROUTING -d 10.96.10.10 -p tcp --dport 9080 \
    -j DNAT --to-destination 10.244.1.10:9080
  in_net iptables -t nat -A PREROUTING -d 10.96.10.11 -p tcp --dport 9080 \
    -m statistic --mode random --probability 0.5 \
    -j DNAT --to-destination 10.244.1.11:9080
  in_net iptables -t nat -A PREROUTING -d 10.96.10.11 -p tcp --dport 9080 \
    -j DNAT --to-destination 10.244.2.11:9080
  in_net iptables -t nat -A PREROUTING -d 10.96.10.12 -p tcp --dport 9080 \
    -j DNAT --to-destination 10.244.2.12:9080
  in_net iptables -t nat -A PREROUTING -d 10.96.10.13 -p tcp --dport 9080 \
    -j DNAT --to-destination 10.244.1.11:9080
  in_net iptables -t nat -A PREROUTING -d 10.96.10.14 -p tcp --dport 9080 \
    -j DNAT --to-destination 10.244.2.11:9080
}

case "${1:-}" in
  up) up ;;
  down) down ;;
  *) echo "usage: $0 up|down" >&2; exit 2 ;;
esac
