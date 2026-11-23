#!/usr/bin/env bash
# Breaks or repairs one of the seven scenarios of Lab 47.1 in the shop.
# Run "break" without reading the scenario first; the lab is to find the
# cause from the symptoms. Scenario 7 needs Istio 1.31 (Kubernetes only).
#
# Usage: ch47/k8s/scenario.sh NUMBER break|fix   (KUBECTL=oc on OpenShift)
# Run it from the root of the companion repository.
set -euo pipefail
K=${KUBECTL:-kubectl}
n=${1:-} action=${2:-}

apply() { $K apply -f - > /dev/null; }
remove() { $K delete --ignore-not-found "$@" > /dev/null; }

case "$n-$action" in
1-break)                                                        # (1)
  apply <<'Y'
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata: {name: orders, namespace: shop}
spec:
  host: orders.shop.svc.cluster.local
  subsets:
  - {name: v1, labels: {version: v1}}
  - {name: v2, labels: {version: v2}}
---
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata: {name: orders, namespace: shop}
spec:
  hosts: [orders.shop.svc.cluster.local]
  http:
  - route:
    - destination: {host: orders.shop.svc.cluster.local, subset: v2}
Y
  ;;
1-fix) remove -n shop virtualservice/orders destinationrule/orders ;;
2-break)                                                        # (2)
  $K create configmap keepalive-server -n shop \
    --from-file=ch27/local/keepalive_server.py --dry-run=client -o yaml |
    apply
  $K apply -f ch27/k8s/keepalive-demo.yaml \
    -f ch24/k8s/40-fortio.yaml > /dev/null
  remove -n shop sidecar/keepalive-demo ;;
2-fix) $K apply -f ch27/istio/keepalive-demo-sidecar.yaml > /dev/null ;;
3-break)                                                        # (3)
  apply <<'Y'
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata: {name: orders, namespace: shop}
spec:
  hosts: [orders.shop.svc.cluster.local]
  http:
  - timeout: 1s
    route:
    - destination: {host: orders.shop.svc.cluster.local}
---
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata: {name: inventory, namespace: shop}
spec:
  hosts: [inventory.shop.svc.cluster.local]
  http:
  - fault: {delay: {fixedDelay: 2s, percentage: {value: 100}}}
    route:
    - destination: {host: inventory.shop.svc.cluster.local}
Y
  ;;
3-fix) remove -n shop virtualservice/orders virtualservice/inventory ;;
4-break)                                                        # (4)
  apply <<'Y'
apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata: {name: default, namespace: shop}
spec:
  mtls: {mode: STRICT}
---
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata: {name: orders, namespace: shop}
spec:
  host: orders.shop.svc.cluster.local
  trafficPolicy:
    tls: {mode: DISABLE}
Y
  $K create namespace legacy --dry-run=client -o yaml | apply
  $K run legacy -n legacy --image=docker.io/curlimages/curl:8.16.0 \
    --restart=Never --command -- sleep 3600 > /dev/null 2>&1 || true ;;
4-fix)
  remove -n shop peerauthentication/default destinationrule/orders
  remove namespace legacy --wait=false ;;
5-break)                                                        # (5)
  apply <<'Y'
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata: {name: inventory-fault-test, namespace: default}
spec:
  hosts: [inventory]
  http:
  - fault: {abort: {httpStatus: 500, percentage: {value: 100}}}
    route:
    - destination: {host: inventory.shop.svc.cluster.local}
Y
  ;;
5-fix) remove -n default virtualservice/inventory-fault-test ;;
6-break)                                                        # (6)
  apply <<'Y'
apiVersion: telemetry.istio.io/v1
kind: Telemetry
metadata: {name: tracing, namespace: shop}
spec:
  tracing:
  - randomSamplingPercentage: 0
Y
  ;;
6-fix) remove -n shop telemetry/tracing ;;
7-break|7-fix)                                                  # (7)
  $K apply -f ch24/k8s/40-fortio.yaml > /dev/null
  $K get configmap istio -n istio-system -o jsonpath='{.data.mesh}' |
    python3 -c '
import json, sys, yaml
mesh = yaml.safe_load(sys.stdin) or {}
if sys.argv[1] == "break":
    mesh["defaultTrafficPolicy"] = {"connectionPool": {
        "tcp": {"maxConnections": 2},
        "http": {"http1MaxPendingRequests": 1}}}
else:
    mesh.pop("defaultTrafficPolicy", None)
print(json.dumps({"data": {"mesh": yaml.safe_dump(mesh)}}))' "$action" |
    $K patch configmap istio -n istio-system --type merge \
      --patch-file /dev/stdin > /dev/null ;;
*) sed -n '2,7p' "$0"; exit 2 ;;
esac
echo "scenario $n: $action done"
