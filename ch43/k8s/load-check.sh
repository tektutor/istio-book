#!/usr/bin/env bash
# Sends 10 requests per second to Bookinfo through the gateway for the
# given time and prints how many answers had each status code.
#
# Usage: ch43/k8s/load-check.sh [duration]          (default: 60s)
kubectl exec -n load deploy/fortio -c fortio -- \
  fortio load -qps 10 -c 2 -t "${1:-60s}" \
  -H "Host: bookinfo.tektutor.test" \
  http://public-istio.ingress/productpage 2>&1 |
  grep -E "^Code|All done"                                      # (1)
