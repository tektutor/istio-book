#!/usr/bin/env bash
# Checks the OpenShift lab on OpenShift Local: your login, the cluster
# version, the mesh, the project labels, and TekTutor Shop running with
# sidecars. It reports every problem instead of stopping at the first.
#
# Usage: ch08/scripts/check-lab-ocp.sh [project]     default: shop
set -uo pipefail

PROJECT=${1:-shop}
FAILED=0
ok()   { printf '  ok    %s\n' "$*"; }
fail() { printf '  FAIL  %s\n' "$*"; FAILED=$((FAILED + 1)); }

echo "OpenShift"
for tool in oc istioctl jq curl; do
  if command -v "$tool" >/dev/null; then ok "$tool"
  else fail "$tool is not on your PATH"; fi
done

if ! user=$(oc whoami 2>/dev/null); then                      # (1)
  fail "not logged in; run oc login first"
  echo "$FAILED check(s) failed."
  exit 1
fi
ok "logged in as $user"

version=$(oc get clusterversion version \
            -o jsonpath='{.status.desired.version}' 2>/dev/null)
case "$version" in                                            # (2)
  4.2[0-9].*) ok "OpenShift $version" ;;
  *)          fail "OpenShift '$version'; OSSM 3.4 needs 4.20 or later" ;;
esac

state=$(oc get istio default -o jsonpath='{.status.state}' 2>/dev/null)
if [ "$state" = Healthy ]; then ok "Istio default is Healthy"  # (3)
else fail "Istio default is '${state:-missing}'; run install-mesh.sh"; fi
state=$(oc get istiocni default -o jsonpath='{.status.state}' 2>/dev/null)
if [ "$state" = Healthy ]; then ok "IstioCNI default is Healthy"
else fail "IstioCNI default is '${state:-missing}'"; fi

labels=$(oc get namespace "$PROJECT" -o json 2>/dev/null |
         jq -c '.metadata.labels // {}')
if jq -e '."istio-discovery" == "enabled"' <<<"$labels" >/dev/null
then ok "project $PROJECT is watched by istiod"
else fail "project $PROJECT has no istio-discovery label"; fi
if jq -e '."istio-injection" == "enabled" or has("istio.io/rev")' \
     <<<"$labels" >/dev/null
then ok "project $PROJECT has an injection label"
else fail "project $PROJECT has no injection label"; fi

for app in inventory orders curl; do                          # (4)
  if ! pods=$(oc get pods -n "$PROJECT" -l "app=$app" -o json 2>/dev/null)
  then
    fail "$app: cannot list pods"
    continue
  fi
  ready=$(jq '[.items[] | select(any(.status.conditions[]?;
          .type == "Ready" and .status == "True"))] | length' <<<"$pods")
  proxy=$(jq '[.items[0].spec | (.containers + (.initContainers // []))[]
          | select(.name == "istio-proxy")] | length' <<<"$pods")
  if [ "$ready" -ge 1 ] && [ "$proxy" -eq 1 ]; then
    ok "$app ready, with sidecar"
  else
    fail "$app: $ready ready pod(s), $proxy sidecar(s)"
  fi
done

if oc exec -n "$PROJECT" deploy/curl -c curl -- \
     curl -fsS http://orders:8080/api/orders/1001 2>/dev/null |
     jq -e '.stock.available' >/dev/null; then
  ok "curl -> orders -> inventory works"
else
  fail "the call from curl to orders failed"
fi

if [ "$FAILED" -eq 0 ]; then echo "All checks passed."
else echo "$FAILED check(s) failed."; exit 1; fi
