#!/usr/bin/env bash
# Installs the tools of the pipeline at fixed versions into ./bin, and
# puts ./bin on the PATH of the later steps of a GitHub Actions job.
set -euo pipefail
ISTIO=1.31.1 KUBECONFORM=0.8.0 CONFTEST=0.71.1 KIND=0.33.0

get() {                                   # get OWNER/REPO TAG FILE
  curl -sSL "https://github.com/$1/releases/download/$2/$3"
}

mkdir -p bin && cd bin
get istio/istio "$ISTIO" "istioctl-$ISTIO-linux-amd64.tar.gz" | tar xz
get yannh/kubeconform "v$KUBECONFORM" kubeconform-linux-amd64.tar.gz |
  tar xz kubeconform
get open-policy-agent/conftest "v$CONFTEST" \
  "conftest_${CONFTEST}_Linux_x86_64.tar.gz" | tar xz conftest
get kubernetes-sigs/kind "v$KIND" kind-linux-amd64 > kind
chmod +x kind
echo "$PWD" >> "${GITHUB_PATH:-/dev/null}"
./istioctl version --remote=false; ./kubeconform -v; ./conftest --version
