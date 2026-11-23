#!/usr/bin/env bash
# Builds the image tektutor/frontend:1.1: the frontend from shop/frontend
# with the files from ch35/frontend laid over it. Then loads the image
# into the minikube profile lab.
#
# Usage: ch35/frontend/build-frontend.sh    (from the repository root)
set -euo pipefail

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cp -r shop/frontend/. "$WORK"
cp ch35/frontend/package.json ch35/frontend/package-lock.json "$WORK/" # (1)
cp ch35/frontend/src/tracing.js ch35/frontend/src/main.jsx \
  ch35/frontend/src/App.jsx "$WORK/src/"
docker build -t tektutor/frontend:1.1 "$WORK"
minikube -p lab image load tektutor/frontend:1.1
