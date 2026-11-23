#!/usr/bin/env bash
# Installs OpenShift Service Mesh 3.4 on OpenShift Local for the labs:
# the operator, the Istio CNI agent and the control plane. Chapter 10
# explains every file it applies. Run it as kubeadmin from the root of
# the companion repository.
#
# Usage: ch08/openshift/install-mesh.sh
set -euo pipefail

# 1. The operator. The subscription waits for manual approval.  # (1)
oc apply -f ch10/operator/subscription.yaml
echo "waiting for the install plan..."
CSV=servicemeshoperator3.v3.4.             # only a 3.4 version of the operator
until plan=$(oc get installplan -n openshift-operators -o json | jq -r \
    --arg csv "$CSV" '.items[] | select(.spec.approved == false)
     | select(any(.spec.clusterServiceVersionNames[]; startswith($csv)))
     | select(all(.spec.clusterServiceVersionNames[];
                  startswith($csv) or startswith("kiali-operator.")))
     | .metadata.name' | head -1) && [ -n "$plan" ]; do
  sleep 5
done
oc patch installplan "$plan" -n openshift-operators --type merge \
  -p '{"spec":{"approved":true}}'
CRDS="istios istiocnis istiorevisions istiorevisiontags ztunnels"
for c in $CRDS; do                                             # (2)
  until oc get crd "$c.sailoperator.io" >/dev/null 2>&1; do sleep 5; done
  oc wait --for=condition=Established "crd/$c.sailoperator.io" --timeout=5m
done

# 2. The CNI agent and the control plane.                     # (3)
oc create namespace istio-cni --dry-run=client -o yaml | oc apply -f -
oc create namespace istio-system --dry-run=client -o yaml | oc apply -f -
oc label namespace istio-system istio-discovery=enabled --overwrite
oc apply -f ch10/mesh/istiocni.yaml
oc apply -f ch10/mesh/istio.yaml
oc wait --for=condition=Ready istios/default --timeout=10m
oc wait --for=condition=Ready istiocnis/default --timeout=5m

# 3. Access logs for the whole mesh, as on the Kubernetes track. # (4)
oc apply -f ch08/istio/access-logs.yaml
oc get istio,istiocni
