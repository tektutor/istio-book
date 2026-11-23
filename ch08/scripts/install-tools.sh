#!/usr/bin/env bash
# Installs the command-line tools for the labs into ~/.local/bin.
# For Linux on x86_64 or arm64. On macOS, use Homebrew (see Chapter 8).
# istioctl comes with the Istio release archive, so it is not here.
#
# Usage: ch08/scripts/install-tools.sh [tool ...]
# With no arguments, it installs every tool in the list below.
set -euo pipefail

MINIKUBE=v1.39.0                                              # (1)
KUBECTL=v1.37.1
HELM=v4.1.4
JQ=1.8.2
YQ=v4.54.1
FORTIO=1.76.0
STEP=0.31.0
ALL_TOOLS=(minikube kubectl helm jq yq fortio step)

[ "$(uname -s)" = Linux ] || { echo "this script is for Linux" >&2; exit 1; }
case "$(uname -m)" in                                         # (2)
  x86_64)        ARCH=amd64 ;;
  aarch64|arm64) ARCH=arm64 ;;
  *) echo "unsupported CPU type: $(uname -m)" >&2; exit 1 ;;
esac

BIN="$HOME/.local/bin"
GH=https://github.com
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$BIN"

get() {          # get URL FILE: download URL into FILE, fail on errors
  curl -fsSL --retry 3 -o "$2" "$1"
}

put() {          # put NAME FILE: install FILE as the program NAME
  install -m 0755 "$2" "$BIN/$1"
  echo "installed $1"
}

install_tool() {                                              # (3)
  case "$1" in
  minikube)
    file="minikube-linux-$ARCH"
    get "$GH/kubernetes/minikube/releases/download/$MINIKUBE/$file" \
        "$TMP/minikube"
    put minikube "$TMP/minikube" ;;
  kubectl)
    get "https://dl.k8s.io/release/$KUBECTL/bin/linux/$ARCH/kubectl" \
        "$TMP/kubectl"
    put kubectl "$TMP/kubectl" ;;
  helm)
    get "https://get.helm.sh/helm-$HELM-linux-$ARCH.tar.gz" "$TMP/helm.tgz"
    tar -xzf "$TMP/helm.tgz" -C "$TMP" "linux-$ARCH/helm"
    put helm "$TMP/linux-$ARCH/helm" ;;
  jq)
    get "$GH/jqlang/jq/releases/download/jq-$JQ/jq-linux-$ARCH" "$TMP/jq"
    put jq "$TMP/jq" ;;
  yq)
    get "$GH/mikefarah/yq/releases/download/$YQ/yq_linux_$ARCH" "$TMP/yq"
    put yq "$TMP/yq" ;;
  fortio)
    file="fortio-linux_$ARCH-$FORTIO.tgz"
    get "$GH/fortio/fortio/releases/download/v$FORTIO/$file" "$TMP/fortio.tgz"
    tar -xzf "$TMP/fortio.tgz" -C "$TMP" usr/bin/fortio
    put fortio "$TMP/usr/bin/fortio" ;;
  step)
    file="step_linux_${STEP}_$ARCH.tar.gz"
    get "$GH/smallstep/cli/releases/download/v$STEP/$file" "$TMP/step.tgz"
    tar -xzf "$TMP/step.tgz" -C "$TMP" "step_$STEP/bin/step"
    put step "$TMP/step_$STEP/bin/step" ;;
  *)
    echo "unknown tool: $1 (choose from: ${ALL_TOOLS[*]})" >&2
    return 1 ;;
  esac
}

if [ $# -gt 0 ]; then TOOLS=("$@"); else TOOLS=("${ALL_TOOLS[@]}"); fi
for tool in "${TOOLS[@]}"; do
  install_tool "$tool"
done

case ":$PATH:" in                                             # (4)
  *":$BIN:"*) ;;
  *) echo "$BIN is not on your PATH. Add this line to ~/.bashrc:"
     echo "  export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
esac
