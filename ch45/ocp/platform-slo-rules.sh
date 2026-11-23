#!/usr/bin/env bash
# OpenShift: wraps platform-slo-rules.yaml in a PrometheusRule for user
# workload monitoring, in the namespace of istiod, whose metrics the rules
# read. Chapter 34 set up the scraping of istiod.
#
# Usage: ch45/ocp/platform-slo-rules.sh [namespace]   (default istio-system)
set -euo pipefail

python3 - "${1:-istio-system}" <<'PY' | oc apply -f -
import json, sys, yaml
rules = yaml.safe_load(open("ch45/prometheus/platform-slo-rules.yaml"))
print(json.dumps({
    "apiVersion": "monitoring.coreos.com/v1",
    "kind": "PrometheusRule",
    "metadata": {"name": "mesh-platform-slo", "namespace": sys.argv[1]},
    "spec": {"groups": rules["groups"]},
}))
PY
