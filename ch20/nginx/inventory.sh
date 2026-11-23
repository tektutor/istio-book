#!/usr/bin/env bash
# Lists every Ingress in the cluster with its class, hosts, number of
# paths and Ingress NGINX annotations, and counts the annotations that
# need manual work in a migration. Needs kubectl and jq.
#
# Usage: ch20/nginx/inventory.sh
set -euo pipefail
PREFIX=nginx.ingress.kubernetes.io/
MANUAL="snippet|auth-|lua|custom-http-errors|whitelist|limit-"
MANUAL="$MANUAL|affinity|session-cookie|use-regex|rewrite-target"

kubectl get ingress -A -o json > /tmp/ingresses.json

jq -r --arg p "$PREFIX" '
  .items[] |
  [ .metadata.namespace + "/" + .metadata.name,
    (.spec.ingressClassName
       // .metadata.annotations["kubernetes.io/ingress.class"] // "-"),
    ([.spec.rules[]?.host] | unique | join(",")),
    ([.spec.rules[]?.http.paths[]?] | length | tostring),
    ([.metadata.annotations // {} | keys[]
      | select(startswith($p)) | ltrimstr($p)] | join(" "))
  ] | @tsv' /tmp/ingresses.json |
  awk -F'\t' 'BEGIN { printf "%-24s %-6s %-20s %-5s %s\n",
                        "INGRESS", "CLASS", "HOSTS", "PATHS", "ANNOTATIONS" }
              { printf "%-24s %-6s %-20s %-5s %s\n", $1, $2, $3, $4, $5 }'

echo
echo "Annotations that need manual work:"
jq -r --arg p "$PREFIX" --arg m "$MANUAL" '
  .items[].metadata.annotations // {} | keys[]
  | select(startswith($p)) | ltrimstr($p) | select(test($m))' \
  /tmp/ingresses.json | sort | uniq -c | sort -rn
