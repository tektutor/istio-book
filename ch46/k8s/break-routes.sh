#!/usr/bin/env bash
# Breaks two routes in the shop namespace for Lab 46.1. Ask a colleague to
# run it, or run it without reading further: the lab is to find the faults
# from their symptoms. ch46/k8s/fix-routes.sh undoes it.
#
# Usage: ch46/k8s/break-routes.sh            (KUBECTL=oc on OpenShift)
set -euo pipefail
K=${KUBECTL:-kubectl}

$K apply -n shop -f - <<'Y'
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata: {name: orders}
spec:
  host: orders.shop.svc.cluster.local
  subsets:
  - name: v1
    labels: {app: orders}
---
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata: {name: orders}
spec:
  hosts: [orders.shop.svc.cluster.local]
  http:
  - route:
    - destination:
        host: orders.shop.svc.cluster.local
        subset: stable                                          # (1)
---
apiVersion: networking.istio.io/v1
kind: Sidecar
metadata: {name: orders}
spec:
  workloadSelector:
    labels: {app: orders}
  outboundTrafficPolicy: {mode: REGISTRY_ONLY}
  egress:
  - hosts: ["istio-system/*"]                                   # (2)
Y
echo "Two routes in the shop namespace are broken."
