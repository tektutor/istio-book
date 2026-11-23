#!/usr/bin/env bash
# Shows four protections of Envoy, configured the way Istio configures
# them: a circuit breaker, outlier detection, a local rate limit and a
# global rate limit with a small rate limit service.
# You need Envoy and fortio on your PATH, and a Python environment with
# the packages of shop/orders and shop/stock (grpcio-tools).
#
# Usage: ch25/local/resilience-demo.sh       (from the repository root)
set -uo pipefail

W=/tmp/ch25
rm -rf $W && mkdir -p $W
PIDS=()
cleanup() { kill "${PIDS[@]}" 2>/dev/null; }
trap cleanup EXIT

inventory() {                     # inventory PORT POD_NAME
  PORT=$1 POD_NAME=$2 python3 shop/inventory/app.py > $W/$2.log 2>&1 &
  PIDS+=($!)
}
inventory 18080 inventory-0
for n in 1 2 3; do inventory 1808$n inventory-$n; done
PORT=18090 POD_NAME=orders-1 INVENTORY_URL=http://127.0.0.1:18080 \
  python3 shop/orders/app.py > $W/orders.log 2>&1 & PIDS+=($!)
cp ch25/local/rls.proto ch25/local/rls.py $W/
(cd $W && python3 -m grpc_tools.protoc -I. --python_out=. \
   --grpc_python_out=. rls.proto)
(cd $W && exec python3 rls.py) > $W/rls.log 2>&1 & PIDS+=($!)
envoy -c ch25/local/resilience-envoy.yaml --base-id 52 --log-level error \
  > $W/envoy.log 2>&1 & PIDS+=($!)
until curl -s http://127.0.0.1:19925/ready 2>/dev/null | grep -q LIVE
do sleep 0.2; done
sleep 1

stats() {                         # stats PATTERN: Envoy counters that match
  curl -s http://127.0.0.1:19925/stats | grep -E "$1" | sed 's/^.*local\.//'
}
codes() { grep -E '^Code' | sed 's/^Code //'; }

echo "### 1. Circuit breaker: 1 connection, 1 waiting request, 3 callers"
curl -s -X POST "http://127.0.0.1:18080/admin/faults?delay=50ms" > /dev/null
fortio load -quiet -c 3 -qps 0 -n 30 \
  http://127.0.0.1:18100/api/stock/SKU-1 2>&1 | codes                # (1)
stats 'inventory.shop.svc.cluster.local.upstream_rq_pending_overflow:'

outlier_run() {                   # outlier_run ADMIN_PORT LISTEN_PORT
  local n before=()
  for n in 1 2 3; do before[n]=$(grep -c ' SKU-1 ' $W/inventory-$n.log); done
  fortio load -quiet -c 1 -qps 20 -n 60 \
    http://127.0.0.1:$2/api/stock/SKU-1 2>&1 | codes                 # (2)
  for n in 1 2 3; do
    echo "inventory-$n answered $(( $(grep -c ' SKU-1 ' \
      $W/inventory-$n.log) - before[n] ))"
  done
  curl -s http://127.0.0.1:$1/stats |
    grep -E 'outlier_detection.ejections_(active|enforced_total|overflow):' |
    sed 's/^.*local\.//'
}
curl -s -X POST "http://127.0.0.1:18082/admin/faults?fail=100" > /dev/null
echo "### 2. Outlier detection: inventory-2 fails every request"
echo "maxEjectionPercent not set, Envoy's default of 10 percent:"
sed -e 's/max_ejection_percent: 100/max_ejection_percent: 10/' \
    -e 's/port_value: 19925/port_value: 19926/' \
    -e 's/port_value: 181\(0[0-3]\)/port_value: 182\1/' \
    ch25/local/resilience-envoy.yaml > $W/envoy-10.yaml                # (3)
envoy -c $W/envoy-10.yaml --base-id 53 --log-level error \
  > $W/envoy-10.log 2>&1 & PIDS+=($!)
until curl -s http://127.0.0.1:19926/ready 2>/dev/null | grep -q LIVE
do sleep 0.2; done
outlier_run 19926 18201
echo "maxEjectionPercent: 100:"
outlier_run 19925 18101

echo "### 3. Local rate limit: 10 per second per pod, 20 per second sent"
fortio load -quiet -c 2 -qps 20 -t 3s \
  http://127.0.0.1:18102/api/orders/7 2>&1 | codes                   # (4)
stats 'http_local_rate_limiter.http_local_rate_limit.rate_limited:'

echo "### 4. Global rate limit: 10 per second per client"
for user in kayal prabhu; do
  qps=20; [ $user = prabhu ] && qps=5
  echo "client $user, $qps per second:"
  fortio load -quiet -c 2 -qps $qps -t 3s -H "x-shop-user: $user" \
    http://127.0.0.1:18103/api/orders/7 2>&1 | codes                 # (5)
done
echo "no client header, 20 per second:"
fortio load -quiet -c 2 -qps 20 -t 3s \
  http://127.0.0.1:18103/api/orders/7 2>&1 | codes
stats 'inbound.8080...ratelimit.(ok|over_limit):' | sed 's/^.*||\.//'
