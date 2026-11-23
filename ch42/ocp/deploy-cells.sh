#!/usr/bin/env bash
# The OpenShift lab: three cells as projects cell-1, cell-2 and cell-3 in
# one cluster, each with its own gateway, and the cell router in the
# project router, reached through an OpenShift Route.
#
# Usage: ch42/ocp/deploy-cells.sh
set -euo pipefail
CODE=$(cd "$(dirname "$0")/.." && pwd)

for n in 1 2 3; do
  c=cell-$n
  sed "s/CELL_NAME/$c/" "$CODE/ocp/cell-project.yaml" | oc apply -f -
  sed "s/CELL_NAME/$c/" "$CODE/cell/app.yaml" |
    oc apply -n "$c" -f -                                       # (1)
  oc annotate gateway cell-gw -n "$c" --overwrite \
    networking.istio.io/service-type=ClusterIP                  # (2)
done

R=$CODE/router
oc apply -f "$R/gateway.yaml"
oc label namespace router istio-discovery=enabled --overwrite
oc annotate gateway cell-router -n router --overwrite \
  networking.istio.io/service-type=ClusterIP
python3 "$R/make-tokens.py" tokens
oc apply -f tokens/request-authn.yaml -f "$R/require-jwt.yaml"
python3 "$R/gen-route.py" --services | oc apply -f -            # (3)
oc create route edge cell-router -n router --service cell-router-istio \
  --port http --hostname cells.apps-crc.testing \
  --dry-run=client -o yaml | oc apply -f -
