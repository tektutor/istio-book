#!/usr/bin/env bash
# Checks a mesh against the hardening checklist of Chapter 33. It only
# reads the cluster. Each line shows PASS or FAIL, the check, and the
# chapter that explains the fix. The exit code is the number of failures.
# You need kubectl (or oc, as KUBECTL=oc), jq and openssl.
#
# Usage: ch33/check/mesh-audit.sh [istio namespace]   (default istio-system)
set -uo pipefail

K=${KUBECTL:-kubectl}
NS=${1:-istio-system}
FAILS=0
result() {                    # result <0 for pass> <check> <chapter>
  if [ "$1" = 0 ]; then printf "PASS  %-46s %s\n" "$2" "$3"
  else printf "FAIL  %-46s %s\n" "$2" "$3"; FAILS=$((FAILS + 1)); fi
}
MESH=$($K get configmap istio -n "$NS" -o jsonpath='{.data.mesh}')     # (1)
MESH_NS=$( { $K get ns -l istio-injection=enabled -o name
             $K get ns -l istio.io/rev -o name
             $K get ns -l istio.io/dataplane-mode=ambient -o name
           } | cut -d/ -f2 | sort -u )

# 1. Mutual TLS
n=$($K get peerauthentication -n "$NS" -o json | jq '[.items[] |
     select(.spec.selector == null and .spec.mtls.mode == "STRICT")] | length')
result $([ "$n" -ge 1 ]; echo $?) "Mesh-wide STRICT mutual TLS" "Ch 30"
# 2. Deny by default in every mesh namespace
for ns in $MESH_NS; do
  n=$($K get authorizationpolicy -n "$ns" -o json | jq '[.items[] |
       select((.spec // {}) == {})] | length')                          # (2)
  result $([ "$n" -ge 1 ]; echo $?) "Deny-by-default policy in $ns" "Ch 31"
done
# 3. Outbound traffic only to registered services
echo "$MESH" | grep -A1 'outboundTrafficPolicy' | grep -q REGISTRY_ONLY
result $? "outboundTrafficPolicy is REGISTRY_ONLY" "Ch 21"
# 4. Own trust domain
td=$(echo "$MESH" | sed -n 's/^trustDomain: *//p')
result $([ -n "$td" ] && [ "$td" != cluster.local ]; echo $?) \
  "Trust domain is not cluster.local ($td)" "Ch 29"
# 5 and 6. Plugged-in CA, with at least 90 days left
if $K get secret cacerts -n "$NS" > /dev/null 2>&1; then
  result 0 "CA from cacerts" "Ch 28"
  for f in ca-cert.pem root-cert.pem; do                               # (3)
    $K get secret cacerts -n "$NS" -o jsonpath="{.data.${f//./\\.}}" |
      base64 -d | openssl x509 -noout -checkend $((90 * 86400)) > /dev/null
    result $? "$f valid for 90 more days" "Ch 29"
  done
else
  result 1 "CA from cacerts" "Ch 28"
fi
# 7. istiod replicas
r=$($K get deployment istiod -n "$NS" -o jsonpath='{.spec.replicas}')
h=$($K get hpa istiod -n "$NS" -o jsonpath='{.spec.minReplicas}' 2>/dev/null)
result $([ "${h:-$r}" -ge 2 ]; echo $?) "istiod runs at least 2 replicas" "Ch 9"
# 8. CNI agent, so that no pod needs NET_ADMIN
$K get daemonset istio-cni-node -n "$NS" > /dev/null 2>&1 ||
  $K get daemonset istio-cni-node -n istio-cni > /dev/null 2>&1
result $? "Istio CNI node agent installed" "Ch 11"
# 9. Distroless images
$K get deployment istiod -n "$NS" \
  -o jsonpath='{.spec.template.spec.containers[0].image}' | grep -q distroless
result $? "istiod uses a distroless image" "Ch 33"
# 10. No EnvoyFilter
n=$($K get envoyfilter -A -o name | wc -l)
result $([ "$n" -eq 0 ]; echo $?) "No EnvoyFilter resources ($n found)" "Ch 25"
# 11 and 12. Pod Security Admission and NetworkPolicy per mesh namespace
for ns in $MESH_NS; do
  lvl=$($K get ns "$ns" \
        -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}')
  result $([ "$lvl" = restricted ] || [ "$lvl" = baseline ]; echo $?) \
    "Pod Security enforced in $ns (${lvl:-none})" "Ch 9"
  n=$($K get networkpolicy -n "$ns" -o name | wc -l)
  result $([ "$n" -ge 1 ]; echo $?) "NetworkPolicy in $ns" "Ch 33"
done
# 13. Limit on downstream connections
echo "$MESH" | grep -q 'overload.global_downstream_max_connections'
result $? "Downstream connection limit set" "Ch 33"
# 14. No gateway listener for every host
n=$( { $K get gateways.networking.istio.io -A -o json 2>/dev/null |
         jq '[.items[].spec.servers[]?.hosts[]? |
              select(. == "*" or endswith("/*"))] | length'
       $K get gateways.gateway.networking.k8s.io -A -o json 2>/dev/null |
         jq '[.items[] | select(.spec.gatewayClassName != "istio-waypoint") |
              .spec.listeners[] |
              select(.protocol != "TCP" and .hostname == null)] | length'
     } | awk '{s += $1} END {print s + 0}')                            # (4)
result $([ "$n" -eq 0 ]; echo $?) "No gateway accepts every host ($n found)" \
  "Ch 33"
echo "$FAILS checks failed"
exit "$FAILS"
