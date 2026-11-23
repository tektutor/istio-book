#!/usr/bin/env bash
# The local ambient lab: two nodes with real ztunnels, Bookinfo stand-ins
# in network namespaces, and Envoy waypoints. Run it as root on Linux.
#
#   lab.sh up [change ...]       build everything; changes as in config
#   lab.sh config [change ...]   new ztunnel configuration: xds/base.yaml
#                                plus the change files, then restart the
#                                ztunnels (istiod would push it instead)
#   lab.sh waypoint NAME start|stop
#   lab.sh routes NAME FILE ...  install route files into a waypoint
#   lab.sh enroll POD | unenroll POD
#   lab.sh ztunnel NODE start|stop
#   lab.sh sidecar POD start|stop [strict|permissive]
#   lab.sh dump NODE             write ztunnel's config dump, print path
#   lab.sh down
#
# You need ztunnel and nodeagent (see build-ztunnel.sh), envoy-contrib,
# python3, iptables, curl and openssl. LAB sets the state folder.
set -euo pipefail
DIR=$(cd "$(dirname "$0")" && pwd)
LAB=${LAB:-/tmp/ambient-lab}
ENVOY=${ENVOY:-envoy-contrib}
ZTUNNEL_SRC=${ZTUNNEL_SRC:-$LAB/ztunnel-src}

pods() { grep -v '^#' "$DIR/pods.txt"; }
field() { pods | awk -v p="$1" -v f="$2" '$1 == p {print $f}'; }   # POD COLUMN
ambient_pods() { pods | awk 'NF && $6 != "waypoint" {print $1}'; }
waypoints() { pods | awk '$6 == "waypoint" {print $1}'; }

stop_pid() {                                  # stop_pid FILE
  [[ -f $1 ]] || return 0
  local pid
  pid=$(cat "$1")
  kill "$pid" 2>/dev/null || true
  rm -f "$1"
  # ztunnel drains open connections for up to five seconds.
  for _ in $(seq 50); do kill -0 "$pid" 2>/dev/null || return 0; sleep 0.2; done
}

# One line per pod in the pods file of its node, which nodeagent follows.
pod_line() {
  echo "$1 $1 $(field "$1" 2) $1 $(field "$1" 5)"
}

enroll() {                                    # (1)
  local pod=$1 node
  node=$(field "$pod" 3)
  ip netns exec "$pod" iptables-restore < "$DIR/inpod-rules.v4"
  ip -n "$pod" rule add fwmark 0x111/0xfff pref 32764 lookup 100
  ip -n "$pod" route add local 0.0.0.0/0 dev lo table 100
  pod_line "$pod" >> "$LAB/$node/pods"
}

unenroll() {
  local pod=$1 node
  node=$(field "$pod" 3)
  sed -i "/^$pod /d" "$LAB/$node/pods"
  ip netns exec "$pod" iptables -t nat -F
  ip netns exec "$pod" iptables -t mangle -F
  ip -n "$pod" rule del fwmark 0x111/0xfff pref 32764 lookup 100 || true
  ip -n "$pod" route flush table 100 || true
}

ztunnel_ctl() {                               # ztunnel_ctl NODE start|stop
  local node=$1
  stop_pid "$LAB/$node/ztunnel.pid"
  [[ $2 == stop ]] && return 0
  ip netns exec "ztunnel-$node" env \
    PROXY_MODE=shared INPOD_UDS="$LAB/$node/ztunnel.sock" \
    XDS_ADDRESS= LOCAL_XDS_PATH="$LAB/config.yaml" FAKE_CA=true \
    NODE_NAME="$node" CLUSTER_ID=Kubernetes IPV6_ENABLED=false \
    ztunnel >> "$LAB/$node/ztunnel.log" 2>&1 &              # (2)
  echo $! > "$LAB/$node/ztunnel.pid"
  until ip netns exec "ztunnel-$node" \
      curl -sf -o /dev/null localhost:15021/healthz/ready; do
    kill -0 "$(cat "$LAB/$node/ztunnel.pid")" 2>/dev/null ||
      { grep '^Error' "$LAB/$node/ztunnel.log" | tail -1; exit 1; }
    sleep 0.2
  done
}

config() {                                    # config [change ...]
  local changes=()
  for c in "$@"; do changes+=("$DIR/xds/$c.yaml"); done
  python3 "$DIR/xds/compose.py" "$DIR/xds/base.yaml" \
    ${changes[@]+"${changes[@]}"} > "$LAB/config.yaml"
  for node in lab lab-m02; do ztunnel_ctl "$node" start; done
  sleep 1                                     # nodeagent sends the pods
}

waypoint_ctl() {                              # waypoint_ctl NAME start|stop
  local name=$1 dir=$LAB/$1
  pkill -f "$ENVOY -c $dir/envoy.yaml" || true
  [[ $2 == stop ]] && return 0
  mkdir -p "$dir/routes"
  [[ -f $dir/cert.pem ]] ||
    "$DIR/waypoint/certs.sh" "$ZTUNNEL_SRC" "$dir" "$name" > /dev/null
  cp "$DIR"/waypoint/routes/*.yaml "$dir/routes/"
  sed "s|WAYPOINT_DIR|$dir|g; s|waypoint\.bookinfo|$name.bookinfo|g" \
    "$DIR/waypoint/waypoint-envoy.yaml" > "$dir/envoy.yaml"
  # Envoy stops when its parent exits, so a subshell stays as its parent.
  (ip netns exec "$name" "$ENVOY" -c "$dir/envoy.yaml" --log-level warn \
    --file-flush-interval-msec 100 \
    --base-id "$(field "$name" 4 | awk -F. '{print $3 * 100 + $4}')" \
    > "$dir/access.log" 2>&1; true) > /dev/null 2>&1 &
  until ip netns exec "$name" curl -s localhost:15000/ready | grep -q LIVE; do
    sleep 0.2
  done
}

routes() {                                    # routes NAME FILE ...
  local dir=$LAB/$1 base; shift
  for f in "$@"; do                           # (3)
    base=$(basename "$f" .yaml)
    cp "$DIR/waypoint/$f" "$dir/routes/.new"
    mv "$dir/routes/.new" "$dir/routes/${base%%-*}.yaml"
  done
  sleep 1
}

sidecar_ctl() {                               # sidecar_ctl POD start|stop [mode]
  local pod=$1 dir=$LAB/$1 list
  pkill -f "$ENVOY -c $dir/sidecar.yaml" || true
  touch "$LAB/sidecars"
  sed -i "/^$pod$/d" "$LAB/sidecars"
  if [[ $2 == stop ]]; then
    ip netns exec "$pod" iptables -t nat -F
    return 0
  fi
  grep -q "^$pod " "$LAB/$(field "$pod" 3)/pods" && unenroll "$pod"
  echo "$pod" >> "$LAB/sidecars"
  mkdir -p "$dir"
  [[ -f $dir/cert.pem ]] ||
    "$DIR/waypoint/certs.sh" "$ZTUNNEL_SRC" "$dir" "$(field "$pod" 5)" \
      > /dev/null
  : > "$dir/access.log"
  chown -R 1337:1337 "$dir"                   # Envoy runs as user 1337
  ip netns exec "$pod" iptables -t nat -F
  ip netns exec "$pod" iptables-restore < "$DIR/sidecar/sidecar-rules.v4"  # (4)
  list=$(paste -sd, "$LAB/sidecars")
  python3 "$DIR/sidecar/sidecar.py" "$pod" "$LAB/config.yaml" "$dir" "$list" \
    "${3:-strict}" > "$dir/sidecar.yaml"
  (ip netns exec "$pod" setpriv --reuid 1337 --regid 1337 --clear-groups \
    "$ENVOY" -c "$dir/sidecar.yaml" --log-level warn \
    --file-flush-interval-msec 100 \
    --base-id "$(field "$pod" 4 | awk -F. '{print $3 * 100 + $4 + 5000}')" \
    > "$dir/access.log" 2>&1; true) > /dev/null 2>&1 &              # (5)
  until ip netns exec "$pod" curl -s localhost:15000/ready | grep -q LIVE; do
    grep -m1 critical "$dir/access.log" && exit 1
    sleep 0.2
  done
}

up() {
  down
  mkdir -p "$LAB/lab" "$LAB/lab-m02"
  [[ -d $ZTUNNEL_SRC/src/tls ]] ||
    git clone -q --depth 1 -b release-1.31 \
      https://github.com/istio/ztunnel.git "$ZTUNNEL_SRC"
  "$DIR/net.sh" up
  : > "$LAB/lab/pods"; : > "$LAB/lab-m02/pods"
  for pod in $(ambient_pods); do
    enroll "$pod"
    role=$(field "$pod" 6)
    [[ $role == client ]] && continue
    ip netns exec "$pod" env ROLE="${role%%:*}" VERSION="${role##*:}" \
      POD_NAME="$pod" python3 "$DIR/bookinfo.py" > "$LAB/$pod.log" 2>&1 &
    echo $! > "$LAB/$pod.pid"
  done
  for node in lab lab-m02; do
    ip netns exec "ztunnel-$node" env INPOD_UDS="$LAB/$node/ztunnel.sock" \
      nodeagent "$LAB/$node/pods" > "$LAB/$node/nodeagent.log" 2>&1 &
    echo $! > "$LAB/$node/nodeagent.pid"
  done
  sleep 0.5
  config "$@"
}

down() {
  for w in $(waypoints); do waypoint_ctl "$w" stop; done
  [[ -f $LAB/sidecars ]] && for p in $(cat "$LAB/sidecars"); do
    sidecar_ctl "$p" stop; done
  for f in "$LAB"/*.pid "$LAB"/*/*.pid; do stop_pid "$f"; done
  "$DIR/net.sh" down
}

cmd=${1:-}; shift || true
case $cmd in
  up) up "$@" ;;
  down) down ;;
  config) config "$@" ;;
  waypoint) waypoint_ctl "$1" "$2" ;;
  routes) routes "$@" ;;
  enroll) enroll "$1" ;;
  unenroll) unenroll "$1" ;;
  ztunnel) ztunnel_ctl "$1" "$2" ;;
  sidecar) sidecar_ctl "$@" ;;
  dump) ip netns exec "ztunnel-$1" curl -s localhost:15000/config_dump \
          > "$LAB/$1/config_dump.json"; echo "$LAB/$1/config_dump.json" ;;
  *) sed -n '2,16p' "$0"; exit 2 ;;
esac
