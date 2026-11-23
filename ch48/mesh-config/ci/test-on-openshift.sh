#!/usr/bin/env bash
# The cluster stage against a shared OpenShift test cluster that runs
# OpenShift Service Mesh 3.4, the shop and the namespace of
# tests/namespace.yaml. The workflow passes the API URL and the token of
# a service account that may edit shop and legacy, and patch the Argo CD
# Application shop-mesh in openshift-gitops.
set -euo pipefail
APP="application shop-mesh -n openshift-gitops"
OFF='{"spec":{"syncPolicy":{"automated":null}}}'
ON='{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}}'
oc login --server "$OCP_SERVER" --token "$OCP_TOKEN" > /dev/null
oc patch $APP --type merge -p "$OFF"                                # (1)
trap 'oc patch $APP --type merge -p "$ON"' EXIT
oc apply -f tests/clients.yaml
oc wait pod --all -n shop --for=condition=Ready --timeout=180s
oc wait pod --all -n legacy --for=condition=Ready --timeout=180s
oc apply -f shop/                                                   # (2)
istioctl analyze -n shop --failure-threshold Warning
KUBECTL=oc python3 tests/mesh_tests.py tests/cases.txt
