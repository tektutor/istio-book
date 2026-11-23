#!/usr/bin/env bash
# Removes the faults of ch46/k8s/break-routes.sh.
#
# Usage: ch46/k8s/fix-routes.sh              (KUBECTL=oc on OpenShift)
set -euo pipefail
K=${KUBECTL:-kubectl}
$K delete -n shop --ignore-not-found virtualservice/orders \
  destinationrule/orders sidecar/orders
