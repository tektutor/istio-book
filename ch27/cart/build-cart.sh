#!/usr/bin/env bash
# Builds the image tektutor/cart:1.1: the cart from shop/cart with the
# three files from ch27/cart laid over it. Then loads the image into the
# minikube profile lab.
#
# Usage: ch27/cart/build-cart.sh       (from the repository root)
set -euo pipefail

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cp -r shop/cart/. "$WORK"                                      # (1)
cp ch27/cart/pom.xml "$WORK/pom.xml"
cp ch27/cart/CartController.java \
  "$WORK/src/main/java/org/tektutor/shop/cart/CartController.java"
cp ch27/cart/application-mesh.properties "$WORK/src/main/resources/"
docker build -t tektutor/cart:1.1 "$WORK"                       # (2)
minikube -p lab image load tektutor/cart:1.1
