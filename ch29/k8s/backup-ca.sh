#!/usr/bin/env bash
# Saves the cacerts Secret to an encrypted file. Keep the file and the
# passphrase in different places, for example the file in object storage
# and the passphrase in your password manager.
#
# Usage: ch29/k8s/backup-ca.sh <output file> <passphrase file>
#        example: ch29/k8s/backup-ca.sh cacerts-backup.enc ~/.ca-passphrase
set -euo pipefail

OUT=${1:?output file}
PASS=${2:?passphrase file}
kubectl get secret cacerts -n istio-system -o json |
  jq '{apiVersion, kind, type, data,                                     # (1)
       metadata: {name: .metadata.name, namespace: .metadata.namespace}}' |
  openssl enc -aes-256-cbc -pbkdf2 -salt -pass file:"$PASS" -out "$OUT"  # (2)
echo "cacerts saved to $OUT"
