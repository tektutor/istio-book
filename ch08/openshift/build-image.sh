#!/usr/bin/env bash
# The OpenShift counterpart of "docker build" plus "minikube image load":
# builds an image from a folder inside the cluster and tags it in the
# project's image stream, so that pods pull it from the internal registry as
#   image-registry.openshift-image-registry.svc:5000/PROJECT/NAME:TAG
#
# Usage: ch08/openshift/build-image.sh NAME:TAG FOLDER [PROJECT]
#        (from the root of the companion repository; PROJECT defaults to shop)
set -euo pipefail

ref=$1 dir=$2 project=${3:-shop}
name=${ref%%:*} tag=${ref#*:}

oc get bc "$name" -n "$project" > /dev/null 2>&1 ||               # (1)
  oc new-build --binary --strategy=docker --name="$name" -n "$project"
build=$(oc start-build "$name" --from-dir="$dir" -n "$project" -o name)  # (2)
oc wait "$build" -n "$project" --timeout=900s \
  --for=jsonpath='{.status.phase}'=Complete || {                  # (3)
  oc get "$build" -n "$project"
  oc get events -n "$project" --field-selector reason=FailedScheduling | tail -3
  exit 1; }
oc tag "$project/$name:latest" "$project/$name:$tag"              # (4)
