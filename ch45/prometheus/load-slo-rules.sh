#!/usr/bin/env bash
# Puts platform-slo-rules.yaml into the "recording_rules.yml" key of the
# Prometheus add-on's ConfigMap. Chapter 34 uses "rules" and Chapter 44
# "alerts", so the three rule sets live side by side.
#
# Usage: ch45/prometheus/load-slo-rules.sh   (from the repository root)
set -euo pipefail

PATCH=$(python3 -c '
import json, sys
rules = open(sys.argv[1]).read()
print(json.dumps({"data": {"recording_rules.yml": rules}}))' \
  ch45/prometheus/platform-slo-rules.yaml)
kubectl patch configmap prometheus -n istio-system --type merge \
  -p "$PATCH"
