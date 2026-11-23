#!/usr/bin/env bash
# Creates the namespace "fleet" with 50 Services, all in front of one
# small Deployment. The number of Services, not of pods, decides how
# much config every sidecar in the mesh receives.
#
# Usage: ch23/scripts/make-fleet.sh [count]          default: 50
# Set IMAGE to use another image for the Deployment, for example the one
# in the OpenShift internal registry.
set -euo pipefail

COUNT=${1:-50}
IMAGE=${IMAGE:-tektutor/inventory:1.0}
kubectl create namespace fleet --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace fleet istio-injection=enabled --overwrite

kubectl apply -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fleet
  namespace: fleet
spec:
  replicas: 1
  selector:
    matchLabels:
      app: fleet
  template:
    metadata:
      labels:
        app: fleet
    spec:
      containers:
      - name: inventory
        image: $IMAGE
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 8080
        resources:
          requests:
            cpu: 10m
            memory: 48Mi
YAML

for i in $(seq -f "%04g" 1 "$COUNT"); do                         # (1)
  cat <<YAML
---
apiVersion: v1
kind: Service
metadata:
  name: svc-$i
  namespace: fleet
spec:
  selector:
    app: fleet
  ports:
  - name: http
    port: 8080
  - name: grpc
    port: 9090
    targetPort: 8080
YAML
done | kubectl apply -f -
kubectl get services -n fleet --no-headers | wc -l
