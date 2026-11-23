#!/usr/bin/env bash
# OpenShift: runs one PromQL query against the Thanos querier, which answers
# for platform and user workload monitoring together, as the user you are
# logged in as. Prints one line per series: its labels, then its value.
#
# Usage: ch34/prometheus/ocp-query.sh 'PROMQL'
set -euo pipefail

host=$(oc get route thanos-querier -n openshift-monitoring \
  -o jsonpath='{.spec.host}')                                        # (1)
curl -sk -H "Authorization: Bearer $(oc whoami -t)" \
  --data-urlencode "query=$1" "https://$host/api/v1/query" |         # (2)
  jq -r '.data.result[] | "{" + ([.metric | to_entries[]
         | "\(.key)=\"\(.value)\""] | join(", ")) + "} => \(.value[1])"'  # (3)
