#!/usr/bin/env bash
# Issues the waypoint's certificate from the test CA that ztunnel uses
# with FAKE_CA=true, so that ztunnel and the waypoint trust each other.
# In a cluster, istiod's CA issues it, as for every other workload.
#
# Usage: ambient-lab/waypoint/certs.sh ZTUNNEL_SOURCE OUT_DIR [ACCOUNT]
set -euo pipefail
SRC=$1; OUT=$2; SA=${3:-waypoint}
mkdir -p "$OUT"
cp "$SRC/src/tls/root-cert.pem" "$OUT/root-cert.pem"
openssl ecparam -name prime256v1 -genkey -noout -out "$OUT/key.pem"
openssl req -new -key "$OUT/key.pem" -subj "/" -out "$OUT/req.csr" 2>/dev/null
openssl x509 -req -in "$OUT/req.csr" -days 365 -out "$OUT/cert.pem" \
  -CA "$SRC/src/tls/root-cert.pem" -CAkey "$SRC/src/tls/ca-key.pem" \
  -extfile <(printf '%s\n' \
    "subjectAltName=critical,URI:spiffe://tektutor.org/ns/bookinfo/sa/$SA" \
    "keyUsage=critical,digitalSignature,keyEncipherment" \
    "extendedKeyUsage=serverAuth,clientAuth" \
    "basicConstraints=critical,CA:FALSE") 2>/dev/null          # (1)
rm "$OUT/req.csr"
openssl x509 -in "$OUT/cert.pem" -noout -ext subjectAltName
