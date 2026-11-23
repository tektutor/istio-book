#!/usr/bin/env bash
# Creates the Kubernetes lab: a minikube cluster named "lab" with three
# nodes, one per zone. You can run it again at any time: it starts the
# cluster if it is stopped and creates it if it does not exist.
#
# Usage: ch08/scripts/create-lab.sh
set -euo pipefail

PROFILE=lab
K8S_VERSION=v1.37.0
NODES=3
CPUS=2                     # for each node
MEMORY=4g                  # for each node
ZONES=(zone-a zone-b zone-c)

if minikube profile list -o json 2>/dev/null |
     jq -e --arg p "$PROFILE" '.valid[]? | select(.Name == $p)' >/dev/null
then
  minikube start -p "$PROFILE"                                  # (1)
else
  minikube start -p "$PROFILE" --driver=docker \
    --container-runtime=docker \
    --kubernetes-version="$K8S_VERSION" --nodes="$NODES" \
    --cpus="$CPUS" --memory="$MEMORY"                           # (2)
fi

# minikube cannot label nodes when it creates them, so label them now.
# The nodes are named lab, lab-m02 and lab-m03.                 # (3)
i=0
for node in $(kubectl --context "$PROFILE" get nodes \
                -o jsonpath='{.items[*].metadata.name}'); do
  kubectl --context "$PROFILE" label node "$node" --overwrite \
    topology.kubernetes.io/region=lab \
    topology.kubernetes.io/zone="${ZONES[$i]}"
  i=$((i + 1))
done

kubectl --context "$PROFILE" wait --for=condition=Ready nodes --all \
  --timeout=180s
echo "lab ready: minikube profile and kubectl context $PROFILE"
