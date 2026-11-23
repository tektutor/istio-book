#!/usr/bin/env bash
# Creates an intermediate CA for one cluster, signed by the root from
# make-root.sh, and writes the four files that the cacerts Secret needs.
#
# Usage: ch28/ca/make-intermediate.sh <cluster> [directory]
#        example: ch28/ca/make-intermediate.sh lab ca-out
set -euo pipefail

NAME=${1:?cluster name}
OUT=${2:-ca-out}
DIR="$OUT/$NAME"
mkdir -p "$DIR"
cat > "$DIR/intermediate.conf" <<CONF
[req]
distinguished_name = dn
prompt = no
[dn]
O = TekTutor
CN = Istio Intermediate CA $NAME
[ext]
basicConstraints = critical, CA:true, pathlen:0
keyUsage = critical, keyCertSign, cRLSign, digitalSignature
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always
CONF
openssl genrsa -out "$DIR/ca-key.pem" 4096 2>/dev/null
openssl req -new -key "$DIR/ca-key.pem" -config "$DIR/intermediate.conf" \
  -out "$DIR/ca.csr"
openssl x509 -req -in "$DIR/ca.csr" -sha256 -days 730 \
  -CA "$OUT/root/root-cert.pem" -CAkey "$OUT/root/root-key.pem" \
  -CAcreateserial -extfile "$DIR/intermediate.conf" -extensions ext \
  -out "$DIR/ca-cert.pem" 2>/dev/null                                   # (1)
cp "$OUT/root/root-cert.pem" "$DIR/root-cert.pem"                        # (2)
cat "$DIR/ca-cert.pem" "$OUT/root/root-cert.pem" > "$DIR/cert-chain.pem" # (3)
rm "$DIR/ca.csr"
openssl verify -CAfile "$DIR/root-cert.pem" "$DIR/ca-cert.pem"
