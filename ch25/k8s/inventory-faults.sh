#!/usr/bin/env bash
# Sets the faults of one inventory pod only. A call through the Service
# would reach any pod, so the script runs the call inside the pod.
#
# Usage: ch25/k8s/inventory-faults.sh POD "fail=100"
set -euo pipefail

POD=$1
QUERY=${2:-}
kubectl exec -n shop "$POD" -c inventory -- python -c "
import urllib.request as u
r = u.urlopen(u.Request('http://127.0.0.1:8080/admin/faults?$QUERY',
                        method='POST'))
print(r.read().decode().strip())"
