#!/usr/bin/env bash
# Prints the nat rules inside one pod on OpenShift, from the node. The
# restricted-v2 SCC does not let a debug container add NET_ADMIN to an
# application pod, so this script works from a node debug pod instead.
# Run it as kubeadmin.
#
# Usage: ch11/debug/read-rules-ocp.sh NAMESPACE APP   e.g. shop orders
set -euo pipefail

NS=${1:?usage: $0 NAMESPACE APP}
APP=${2:?usage: $0 NAMESPACE APP}

pod=$(oc get pod -n "$NS" -l "app=$APP" -o jsonpath='{.items[0].metadata.name}')
node=$(oc get pod -n "$NS" "$pod" -o jsonpath='{.spec.nodeName}')   # (1)

# Inside the node: find the application container, read its process ID,
# and enter only its network namespace to list the rules.        # (2)
oc debug "node/$node" -q -- chroot /host sh -c "
  id=\$(crictl ps -q --name '^$APP\$' --label io.kubernetes.pod.namespace=$NS \
        --label io.kubernetes.pod.name=$pod)
  pid=\$(crictl inspect --output go-template --template '{{.info.pid}}' \$id)
  nsenter -t \$pid -n iptables-save -t nat"
