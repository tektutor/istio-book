#!/usr/bin/env bash
# Checks that the Kubernetes lab is ready. It reports every problem it
# finds instead of stopping at the first one.
#
# Usage: ch08/scripts/check-lab.sh [tools|cluster|istio|apps|all]
set -uo pipefail

STAGE=${1:-all}
CTX=lab
FAILED=0
ok()   { printf '  ok    %s\n' "$*"; }
fail() { printf '  FAIL  %s\n' "$*"; FAILED=$((FAILED + 1)); }
k()    { kubectl --context "$CTX" "$@"; }

expect() {       # expect OK-TEXT FAIL-TEXT COMMAND...: run it and report
  local good=$1 bad=$2
  shift 2
  if "$@" >/dev/null 2>&1; then ok "$good"; else fail "$bad"; fi
}

check_tools() {                                               # (1)
  echo "Tools"
  for tool in docker minikube kubectl istioctl helm jq yq fortio step curl \
              python3; do
    if command -v "$tool" >/dev/null; then ok "$tool"
    else fail "$tool is not on your PATH"; fi
  done
  local v
  v=$(istioctl version --remote=false -o json 2>/dev/null |
      jq -r '.clientVersion.version' 2>/dev/null)
  case "$v" in
    1.31.*) ok "istioctl version $v" ;;
    *)      fail "istioctl version is '$v', the labs need 1.31.x" ;;
  esac
  if python3 -c 'import sys; sys.exit(sys.version_info < (3, 11))' \
       2>/dev/null; then
    ok "python3 is 3.11 or later"
  else
    fail "python3 is older than 3.11"
  fi
}

check_cluster() {                                             # (2)
  echo "Cluster"
  if ! k get --raw /readyz >/dev/null 2>&1; then
    fail "cannot reach the cluster with context $CTX"
    return
  fi
  ok "context $CTX answers"
  local ready zones images
  ready=$(k get nodes -o json | jq '[.items[] | select(any(
          .status.conditions[]; .type == "Ready" and .status == "True"))]
          | length')
  expect "3 nodes Ready" "$ready nodes Ready, expected 3" [ "$ready" -eq 3 ]
  zones=$(k get nodes -o json | jq '[.items[].metadata.labels
          ["topology.kubernetes.io/zone"] // empty] | unique | length')
  expect "nodes in 3 zones" "nodes in $zones zones, expected 3" \
    [ "$zones" -eq 3 ]
  images=$(minikube -p lab image ls 2>/dev/null | grep -c tektutor/ || true)
  expect "shop images loaded" "shop images missing; run load-shop-images.sh" \
    [ "$images" -ge 2 ]
}

check_istio() {                                               # (3)
  echo "Istio"
  local image avail
  image=$(k get deploy istiod -n istio-system \
          -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)
  case "$image" in
    *:1.31.*) ok "istiod image $image" ;;
    "")       fail "no istiod Deployment in istio-system" ;;
    *)        fail "istiod image is $image, expected version 1.31.x" ;;
  esac
  avail=$(k get deploy istiod -n istio-system \
          -o jsonpath='{.status.availableReplicas}' 2>/dev/null)
  expect "istiod available ($avail)" "istiod has no available replica" \
    [ "${avail:-0}" -ge 1 ]
  expect "Gateway API CRDs installed" "Gateway API CRDs missing" \
    k get crd gateways.gateway.networking.k8s.io
  expect "access logs on (Telemetry mesh-default)" \
    "Telemetry mesh-default missing" \
    k get telemetry mesh-default -n istio-system
}

check_app() {    # check_app NAMESPACE APP: one ready pod in the mesh
  local pods ready proxy mode
  pods=$(k get pods -n "$1" -l "app=$2" -o json 2>/dev/null) ||
    { fail "$1/$2: cannot list pods"; return; }
  ready=$(jq '[.items[] | select(any(.status.conditions[]?;
          .type == "Ready" and .status == "True"))] | length' <<<"$pods")
  proxy=$(jq '[.items[0].spec | (.containers + (.initContainers // []))[]
          | select(.name == "istio-proxy")] | length' <<<"$pods")
  mode=$(k get namespace "$1" \
           -o jsonpath='{.metadata.labels.istio\.io/dataplane-mode}')
  if [ "$ready" -lt 1 ]; then
    fail "$1/$2 has no ready pod"
  elif [ "$mode" = ambient ] && [ "$proxy" -eq 0 ]; then
    ok "$1/$2 ready, in ambient mode"
  elif [ "$proxy" -eq 1 ]; then
    ok "$1/$2 ready, with sidecar"
  else
    fail "$1/$2 ready, but not in the mesh"
  fi
}

check_apps() {                                                # (4)
  echo "Sample applications"
  for app in inventory orders curl; do check_app shop "$app"; done
  for app in productpage details ratings reviews; do
    check_app bookinfo "$app"
  done
  if k exec -n shop deploy/curl -c curl -- \
       curl -fsS http://orders:8080/api/orders/1001 2>/dev/null |
       jq -e '.stock.available' >/dev/null; then
    ok "curl -> orders -> inventory works"
  else
    fail "the call from curl to orders failed"
  fi
}

case "$STAGE" in
  tools)   check_tools ;;
  cluster) check_cluster ;;
  istio)   check_istio ;;
  apps)    check_apps ;;
  all)     check_tools; check_cluster; check_istio; check_apps ;;
  *)       echo "usage: $0 [tools|cluster|istio|apps|all]" >&2; exit 2 ;;
esac

if [ "$FAILED" -eq 0 ]; then echo "All checks passed."
else echo "$FAILED check(s) failed."; exit 1; fi
