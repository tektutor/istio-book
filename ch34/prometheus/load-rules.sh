#!/usr/bin/env bash
# Puts slo-rules.yaml into the "rules" key of the Prometheus add-on's
# ConfigMap. Prometheus reads that key as a rule file; its reloader
# container notices the change within about a minute.
#
# Usage: ch34/prometheus/load-rules.sh       (from the repository root)
set -euo pipefail

PATCH=$(python3 -c '
import json, sys
print(json.dumps({"data": {"rules": open(sys.argv[1]).read()}}))' \
  ch34/prometheus/slo-rules.yaml)
kubectl patch configmap prometheus -n istio-system --type merge \
  -p "$PATCH"
