#!/usr/bin/env bash
# OpenShift: builds frontend 1.1 inside the cluster from the same files as
# ch35/frontend/build-frontend.sh, and tags it frontend:1.1 in the shop
# project.
#
# Usage: ch35/ocp/build-frontend.sh    (from the repository root)
set -euo pipefail

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cp -r shop/frontend/. "$WORK"
cp ch35/frontend/package.json ch35/frontend/package-lock.json "$WORK/"
cp ch35/frontend/src/tracing.js ch35/frontend/src/main.jsx \
  ch35/frontend/src/App.jsx "$WORK/src/"
ch08/openshift/build-image.sh frontend:1.1 "$WORK"
