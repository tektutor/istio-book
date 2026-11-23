#!/usr/bin/env bash
# Creates a stand-in for a corporate root CA: a self-signed certificate
# that is valid for 10 years, and its private key. In a real company,
# the root key stays offline, often in a hardware security module.
#
# Usage: ch28/ca/make-root.sh [directory] [name]
#        (defaults: ca-out, "TekTutor Root CA")
set -euo pipefail

OUT=${1:-ca-out}
NAME=${2:-TekTutor Root CA}
mkdir -p "$OUT/root"
cat > "$OUT/root/root.conf" <<CONF
[req]
distinguished_name = dn
prompt = no
x509_extensions = ext
[dn]
O = TekTutor
CN = $NAME
[ext]
basicConstraints = critical, CA:true
keyUsage = critical, keyCertSign, cRLSign
subjectKeyIdentifier = hash
CONF
openssl genrsa -out "$OUT/root/root-key.pem" 4096 2>/dev/null          # (1)
openssl req -x509 -new -key "$OUT/root/root-key.pem" -sha256 \
  -days 3650 -config "$OUT/root/root.conf" \
  -out "$OUT/root/root-cert.pem"                                        # (2)
echo "root CA written to $OUT/root"
