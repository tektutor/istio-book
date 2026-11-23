#!/usr/bin/env bash
# Moves the shop between sidecar and ambient mode. Run it from the root
# of the repository of Lab 48.1, after the policies of the new mode are in
# place (Lab 50.2, step 6).
#
# Usage: capstone/switch-mode.sh ambient|sidecar      (KUBECTL=oc too)
set -euo pipefail
K=${KUBECTL:-kubectl} NS=shop
case ${1:-} in
ambient)
  $K label namespace $NS istio-injection- \
    istio.io/dataplane-mode=ambient istio.io/use-waypoint=waypoint  # (1)
  $K label service orders -n $NS istio.io/ingress-use-waypoint=true  # (2)
  ;;
sidecar)
  $K label namespace $NS istio.io/dataplane-mode- istio.io/use-waypoint- \
    istio-injection=enabled
  $K label service orders -n $NS istio.io/ingress-use-waypoint-
  ;;
*) echo "usage: $0 ambient|sidecar" >&2; exit 2 ;;
esac
$K rollout restart deployment -n $NS                                 # (3)
$K argo rollouts restart inventory -n $NS
$K delete pod -n $NS -l app=mesh-test --wait                       # (4)
$K apply -f tests/clients.yaml
for d in $($K get deployment -n $NS -o name); do
  $K rollout status -n $NS "$d"
done
