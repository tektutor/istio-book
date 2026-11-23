#!/usr/bin/env bash
# Shows, for every proxy of Bookinfo, the gateway and Fortio, the istiod
# that serves it and the proxy's version.
#
# Usage: ch43/k8s/versions.sh
istioctl proxy-status | awk 'NR == 1 || /bookinfo|ingress|load/ {
  printf "%-44s %-34s %s\n", $1, $3, $4 }'                     # (1)
