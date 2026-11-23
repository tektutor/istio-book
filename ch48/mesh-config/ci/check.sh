#!/usr/bin/env bash
# The static checks for mesh configuration. They need no cluster, so they
# run first in CI, and you can run them before you push.
#
# Usage: ci/check.sh DIR [DIR ...]        run it from the repository root
set -uo pipefail
CATALOG=https://raw.githubusercontent.com/datreeio/CRDs-catalog/main
SCHEMAS="$CATALOG/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json"
mapfile -t files < <(find "$@" -name '*.yaml' | sort)
failed=0

# istioctl validate prints warnings but still exits 0; treat them as errors.
validate() {
  local out rc
  out=$(istioctl validate "$@" 2>&1); rc=$?
  echo "$out"
  [ "$rc" -eq 0 ] && ! grep -q 'has warnings' <<< "$out"
}

stage() {
  local title=$1; shift
  echo "== $title"
  if "$@" 2>&1 | sed 's/^/   /'; then echo "   pass"
  else echo "   FAIL"; failed=1; fi
}

stage "1 schema" kubeconform -strict -summary \
  -schema-location default -schema-location "$SCHEMAS" "${files[@]}"  # (1)
stage "2a Istio validation" validate \
  $(printf -- '-f %s ' "${files[@]}")                                  # (2)
stage "2b Istio analysis" istioctl analyze --use-kube=false \
  --failure-threshold Warning "${files[@]}"                             # (3)
stage "3 team rules" conftest test --no-color -p policy "${files[@]}"   # (4)
exit $failed
