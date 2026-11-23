#!/usr/bin/env bash
# Imports shop-slo.json into the Grafana add-on through its HTTP API.
# The add-on lets anonymous users act as administrators, so the call
# needs no password; a production Grafana needs a service account token
# in an "Authorization: Bearer" header.
#
# Usage: ch34/grafana/import-dashboard.sh    (from the repository root)
set -euo pipefail

kubectl port-forward -n istio-system svc/grafana 3000:3000 > /dev/null &
PF=$!
trap 'kill $PF' EXIT
until curl -s -o /dev/null http://127.0.0.1:3000/api/health; do sleep 0.5; done
python3 -c '
import json, sys
print(json.dumps({"dashboard": json.load(open(sys.argv[1])),
                  "overwrite": True}))' ch34/grafana/shop-slo.json |
  curl -s -H "Content-Type: application/json" --data @- \
    http://127.0.0.1:3000/api/dashboards/db                     # (1)
echo
