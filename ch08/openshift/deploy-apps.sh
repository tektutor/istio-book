#!/usr/bin/env bash
# Creates the shop and bookinfo projects on OpenShift Local, adds them
# to the mesh, builds the TekTutor Shop images inside the cluster and
# deploys both applications. Run it as kubeadmin from the root of the
# companion repository, after install-mesh.sh.
#
# Usage: ch08/openshift/deploy-apps.sh
set -euo pipefail

ISTIO_HOME=${ISTIO_HOME:?set ISTIO_HOME to the Istio 1.31.1 archive folder}

for project in shop bookinfo; do                              # (1)
  oc new-project "$project" >/dev/null 2>&1 || true
  ch10/enrol/enrol-project.sh "$project"
done

# TekTutor Shop: build the images in the cluster, as in Chapter 1.  # (2)
oc project shop
for service in inventory orders; do
  oc get bc "$service" >/dev/null 2>&1 ||
    oc new-build --binary --strategy=docker --name="$service"
  oc start-build "$service" --from-dir="shop/$service" --follow
done
for f in ch01/openshift/*.yaml; do
  sed "s/PROJECT/shop/" "$f" | oc apply -f -
done

# Bookinfo, with images from Docker Hub as in Chapter 8.       # (3)
sed 's#registry.istio.io/release#docker.io/istio#' \
  "$ISTIO_HOME/samples/bookinfo/platform/kube/bookinfo.yaml" |
  oc apply -n bookinfo -f -

oc wait -n shop --for=condition=Ready pod -l app --timeout=300s
oc wait -n bookinfo --for=condition=Ready pod --all --timeout=600s
