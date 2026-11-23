#!/usr/bin/env bash
# OpenShift: wraps slo-rules.yaml in a PrometheusRule for user workload
# monitoring, in the project of the services it measures.
#
# Usage: ch34/prometheus/ocp-rules.sh [project]   (default: shop)
set -euo pipefail

python3 - "${1:-shop}" <<'PY' | oc apply -f -
import json, sys, yaml
rules = yaml.safe_load(open("ch34/prometheus/slo-rules.yaml"))
print(json.dumps({
    "apiVersion": "monitoring.coreos.com/v1",
    "kind": "PrometheusRule",
    "metadata": {"name": "istio-slo", "namespace": sys.argv[1]},
    "spec": {"groups": rules["groups"]},
}))
PY
