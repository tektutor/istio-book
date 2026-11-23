#!/usr/bin/env bash
# Calls "where" N times from the curl pod in zone-a and counts the zones
# that answered, and the errors. The virtual machine of Lab 41.2 answers
# with the zone "vm".
# Usage: ch41/k8s/count.sh [N]        (default: 30)
N=${1:-30}
kubectl exec -n zones curl -c curl -- sh -c "
  for i in \$(seq $N); do
    curl -s -m 5 -w ' %{http_code}\n' http://where:8080/
  done" |
  awk '/ 200$/ { match($0, /"zone": "[^"]*"/)
                 z[substr($0, RSTART + 9, RLENGTH - 10)]++; next }
       { z["errors"]++ }
       END { for (k in z) printf "%-7s %d\n", k, z[k] }' | sort
