#!/usr/bin/env bash
# Adds an OpenShift project to the mesh. Run it as a cluster
# administrator; project users cannot change namespace labels.
#
# Usage: ch10/enrol/enrol-project.sh PROJECT [REVISION]
# With no REVISION, the project uses istio-injection=enabled, which
# works for an Istio resource named "default".
set -euo pipefail

PROJECT=${1:?usage: $0 PROJECT [REVISION]}
REVISION=${2:-}

oc label namespace "$PROJECT" istio-discovery=enabled --overwrite   # (1)
if [ -z "$REVISION" ]; then
  oc label namespace "$PROJECT" istio-injection=enabled --overwrite
else
  oc label namespace "$PROJECT" istio.io/rev="$REVISION" \
    istio-injection- --overwrite                                    # (2)
fi
oc get namespace "$PROJECT" --show-labels
