#!/usr/bin/env bash
# OpenShift: builds cart 1.1 inside the cluster from the same files as
# ch27/cart/build-cart.sh, and tags it cart:1.1 in the shop project.
#
# Usage: ch27/ocp/build-cart.sh    (from the repository root)
set -euo pipefail

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cp -r shop/cart/. "$WORK"
cp ch27/cart/pom.xml "$WORK/pom.xml"
cp ch27/cart/CartController.java \
  "$WORK/src/main/java/org/tektutor/shop/cart/CartController.java"
cp ch27/cart/application-mesh.properties "$WORK/src/main/resources/"
ch08/openshift/build-image.sh cart:1.1 "$WORK"
