#!/usr/bin/env bash
# Builds the TekTutor Shop images and loads them into every node of the
# lab cluster. Run it from the root of the companion repository.
#
# Usage: ch08/scripts/load-shop-images.sh [tag]     default tag: 1.0
set -euo pipefail

PROFILE=lab
TAG=${1:-1.0}

for service in inventory orders; do
  image="tektutor/$service:$TAG"
  docker build -t "$image" "shop/$service"                      # (1)
  minikube -p "$PROFILE" image load "$image"                    # (2)
done

echo "images in the cluster:"
minikube -p "$PROFILE" image ls | grep tektutor/
