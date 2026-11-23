#!/usr/bin/env bash
# Creates two small certificate authorities and three certificates with
# openssl, for the TLS demo and for Lab 19.2:
#   lab-ca         signs the gateway's server certificate
#   partner-ca     signs the certificates of partner companies
#   server         partner.tektutor.test, signed by lab-ca
#   acme           a client certificate for Acme Books, from partner-ca
#   rogue          a client certificate from a CA that nobody trusts
#
# Usage: ch19/local/make-certs.sh <output folder>
set -euo pipefail
OUT=${1:?output folder}
mkdir -p "$OUT"
cd "$OUT"

ca() {                                    # ca NAME "SUBJECT"
  openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes \
    -keyout "$1.key" -out "$1.crt" -days 365 -subj "$2" 2>/dev/null
}
cert() {                                  # cert NAME CA "SUBJECT" EXT
  openssl req -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes \
    -keyout "$1.key" -out "$1.csr" -subj "$3" 2>/dev/null
  openssl x509 -req -in "$1.csr" -CA "$2.crt" -CAkey "$2.key" \
    -CAcreateserial -out "$1.crt" -days 90 -extfile <(echo "$4") 2>/dev/null
  rm "$1.csr"
}

ca lab-ca "/O=TekTutor Lab/CN=TekTutor Lab CA"
ca partner-ca "/O=TekTutor Shop/CN=TekTutor Partner CA"
ca rogue-ca "/O=Nobody/CN=Untrusted CA"
cert server lab-ca "/CN=partner.tektutor.test" \
  "subjectAltName=DNS:partner.tektutor.test
extendedKeyUsage=serverAuth"
cert acme partner-ca "/O=Acme Books/CN=acme-orders" \
  "subjectAltName=DNS:orders.acme.tektutor.test
extendedKeyUsage=clientAuth"
cert rogue rogue-ca "/O=Rogue/CN=rogue-client" \
  "extendedKeyUsage=clientAuth"
ls *.crt
