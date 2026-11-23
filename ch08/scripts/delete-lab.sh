#!/usr/bin/env bash
# Deletes the Kubernetes lab: the minikube cluster "lab" with everything
# in it, including the images you loaded.
set -euo pipefail

minikube delete -p lab
