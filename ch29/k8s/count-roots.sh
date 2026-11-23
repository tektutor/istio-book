#!/usr/bin/env bash
# Prints the issuer of a workload's certificate and the subjects of the
# roots that its sidecar trusts.
#
# Usage: ch29/k8s/count-roots.sh <deployment> <namespace>
#        example: ch29/k8s/count-roots.sh orders shop
set -euo pipefail

JSON=$(istioctl proxy-config secret deploy/"$1" -n "$2" -o json)
echo "certificate issuer:"
echo "$JSON" | jq -r '.dynamicActiveSecrets[] | select(.name == "default") |
    .secret.tlsCertificate.certificateChain.inlineBytes' | base64 -d |
  openssl x509 -noout -issuer | sed 's/^/  /'
echo "trusted roots:"
echo "$JSON" | jq -r '.dynamicActiveSecrets[] | select(.name == "ROOTCA") |
    .secret.validationContext.trustedCa.inlineBytes' | base64 -d |
  openssl storeutl -noout -text -certs /dev/stdin |
  grep 'Subject:' | sed 's/^ */  /'                                     # (1)
