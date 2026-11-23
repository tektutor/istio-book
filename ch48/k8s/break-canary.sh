#!/usr/bin/env bash
# Makes the canary pods of the inventory Rollout fail PERCENT of their
# requests with 503, through the admin API that inventory has had since
# Chapter 1. The call runs inside each pod, so no policy blocks it.
#
# Usage: ch48/k8s/break-canary.sh [PERCENT]     default 5; 0 repairs
set -euo pipefail
K=${KUBECTL:-kubectl} PERCENT=${1:-5}
hash=$($K get rollout inventory -n shop \
  -o jsonpath='{.status.currentPodHash}')                       # (1)
for pod in $($K get pods -n shop -o name \
    -l "app=inventory,rollouts-pod-template-hash=$hash"); do
  $K exec -n shop "$pod" -c inventory -- python -c "
import urllib.request as r
url = 'http://127.0.0.1:8080/admin/faults?fail=$PERCENT'
print(r.urlopen(r.Request(url, method='POST')).read().decode())"
done
