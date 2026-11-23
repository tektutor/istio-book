#!/usr/bin/env bash
# Puts mesh-alerts.yaml into the "alerts" key of the Prometheus add-on's
# ConfigMap, next to the SLO rules that Chapter 34 put in "rules".
# Prometheus reloads its rule files within about a minute.
#
# Usage: ch44/monitoring/load-alerts.sh     (from the repository root)
set -euo pipefail

PATCH=$(python3 -c '
import json, sys
print(json.dumps({"data": {"alerts": open(sys.argv[1]).read()}}))' \
  ch44/monitoring/mesh-alerts.yaml)
kubectl patch configmap prometheus -n istio-system --type merge \
  -p "$PATCH"
