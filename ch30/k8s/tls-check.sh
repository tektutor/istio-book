#!/usr/bin/env bash
# Counts the requests that a workload's sidecar received, by connection
# security: mutual_tls or none. Run it before you move to STRICT: every
# request counted under "none" would fail.
#
# Usage: ch30/k8s/tls-check.sh <deployment> <namespace>
#        example: ch30/k8s/tls-check.sh orders shop
set -euo pipefail

kubectl exec -n "$2" deploy/"$1" -c istio-proxy -- \
    pilot-agent request GET stats/prometheus |
  grep '^istio_requests_total{' | grep 'reporter="destination"' |      # (1)
  awk '{ pol = $0; sub(/.*connection_security_policy="/, "", pol)
         sub(/".*/, "", pol)
         src = $0; sub(/.*source_workload="/, "", src); sub(/".*/, "", src)
         n[pol " from " src] += $NF }                                   # (2)
       END { for (k in n) print n[k], k }' | sort -rn
