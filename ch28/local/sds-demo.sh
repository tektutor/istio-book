#!/usr/bin/env bash
# Builds a root and an intermediate CA, issues the orders certificate as
# istiod would, hands it to Envoy through SDS, reads it back with
# istioctl, and then replaces it while Envoy runs.
# You need Envoy, istioctl, openssl and python3 with cryptography.
#
# Usage: ch28/local/sds-demo.sh       (from the repository root)
set -euo pipefail

CA=$(mktemp -d)
SDS=/tmp/ch28-sds
rm -rf $SDS; mkdir -p $SDS
ch28/ca/make-root.sh "$CA" > /dev/null
ch28/ca/make-intermediate.sh lab "$CA" > /dev/null

write_secrets() {                                              # (1)
  local dir=$1
  cat > $SDS/default.tmp <<YAML
resources:
- "@type": type.googleapis.com/envoy.extensions.transport_sockets.tls.v3.Secret
  name: default
  tls_certificate:
    certificate_chain: { inline_bytes: $(base64 -w0 "$dir/cert-chain.pem") }
    private_key: { inline_bytes: $(base64 -w0 "$dir/key.pem") }
YAML
  cat > $SDS/ROOTCA.tmp <<YAML
resources:
- "@type": type.googleapis.com/envoy.extensions.transport_sockets.tls.v3.Secret
  name: ROOTCA
  validation_context:
    trusted_ca: { inline_bytes: $(base64 -w0 "$CA/lab/root-cert.pem") }
YAML
  mv $SDS/default.tmp $SDS/default.yaml                        # (2)
  mv $SDS/ROOTCA.tmp $SDS/ROOTCA.yaml
}

show() {
  sleep 1
  curl -s http://127.0.0.1:19930/config_dump > $SDS/dump.json
  istioctl proxy-config secret --file $SDS/dump.json |              # (3)
    sed -E 's/ {2,}/\t/g' |
    awk -F'\t' '{printf "%-14s %-11s %-11s %-14s %s\n", $1, $2, $4,
                  substr($5, 1, 13), $6}'
}

python3 ch28/ca/issue_workload_cert.py "$CA/lab" shop orders > /dev/null
write_secrets "$CA/lab/shop-orders"
envoy -c ch28/local/sds-envoy.yaml --base-id 58 --log-level error \
  > $SDS/envoy.log 2>&1 &
ENVOY=$!
trap 'kill $ENVOY 2>/dev/null; rm -rf "$CA"' EXIT
until curl -s http://127.0.0.1:19930/ready 2>/dev/null | grep -q LIVE
do kill -0 $ENVOY || exit 1; sleep 0.2; done

echo "### The certificate that istiod would issue for shop/orders"
openssl x509 -in "$CA/lab/shop-orders/cert-chain.pem" -noout \
  -subject -issuer -dates -ext subjectAltName,keyUsage,extendedKeyUsage  # (4)
echo "### The secrets in Envoy, read with istioctl"
show
echo "### The same chain, verified against the root"
( cd "$CA/lab" && openssl verify -CAfile root-cert.pem \
    -untrusted ca-cert.pem shop-orders/cert-chain.pem )
echo "### A new certificate, written while Envoy runs"
python3 ch28/ca/issue_workload_cert.py "$CA/lab" shop orders > /dev/null
write_secrets "$CA/lab/shop-orders"
show
