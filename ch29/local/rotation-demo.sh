#!/usr/bin/env bash
# Rotates the root CA under load: publish both roots, switch the signer,
# remove the old root, with Fortio sending 20 requests per second. Then
# repeats the switch without publishing the new root first.
# You need Envoy, fortio, openssl and python3 with cryptography.
#
# Usage: ch29/local/rotation-demo.sh       (from the repository root)
set -uo pipefail

SDS=/tmp/ch29-sds
CA=$(mktemp -d)
rm -rf $SDS; mkdir -p $SDS/orders $SDS/inventory
for r in a b; do                                               # (1)
  ch28/ca/make-root.sh "$CA/$r" "TekTutor Root CA ${r^^}" > /dev/null
  ch28/ca/make-intermediate.sh lab "$CA/$r" > /dev/null
  for sa in orders inventory; do
    python3 ch28/ca/issue_workload_cert.py "$CA/$r/lab" shop $sa > /dev/null
  done
done
cat "$CA/a/root/root-cert.pem" > "$CA/roots-a.pem"
cat "$CA/a/root/root-cert.pem" "$CA/b/root/root-cert.pem" > "$CA/roots-ab.pem"
cat "$CA/b/root/root-cert.pem" > "$CA/roots-b.pem"

# set <workload> <signer a|b> <roots a|ab|b>: rewrite its two SDS secrets
set_sds() {
  local w=$1 dir="$CA/$2/lab/shop-$1" roots="$CA/roots-$3.pem"
  cat > $SDS/$w/default.tmp <<YAML
resources:
- "@type": type.googleapis.com/envoy.extensions.transport_sockets.tls.v3.Secret
  name: default
  tls_certificate:
    certificate_chain: { inline_bytes: $(base64 -w0 "$dir/cert-chain.pem") }
    private_key: { inline_bytes: $(base64 -w0 "$dir/key.pem") }
YAML
  cat > $SDS/$w/ROOTCA.tmp <<YAML
resources:
- "@type": type.googleapis.com/envoy.extensions.transport_sockets.tls.v3.Secret
  name: ROOTCA
  validation_context:
    trusted_ca: { inline_bytes: $(base64 -w0 "$roots") }
YAML
  mv $SDS/$w/ROOTCA.tmp $SDS/$w/ROOTCA.yaml
  mv $SDS/$w/default.tmp $SDS/$w/default.yaml
  printf "%5.1fs  %-9s signer %s, trusts %s\n" \
    "$(echo "$(date +%s.%N) - $START" | bc)" $w ${2^^} ${3^^}
}

echo "### Start: both workloads use root A"
START=$(date +%s.%N)
set_sds orders a a; set_sds inventory a a
envoy -c ch29/local/rotation-envoy.yaml --base-id 59 --log-level error \
  > $SDS/envoy.log 2>&1 &
ENVOY=$!
trap 'kill $ENVOY 2>/dev/null; rm -rf "$CA"' EXIT
until curl -s http://127.0.0.1:19931/ready 2>/dev/null | grep -q LIVE
do kill -0 $ENVOY || exit 1; sleep 0.2; done

echo "### The planned rotation, under load"
START=$(date +%s.%N)
fortio load -quiet -qps 20 -t 24s http://127.0.0.1:18700/ \
  > $SDS/fortio.txt 2>&1 &
LOAD=$!
sleep 3; set_sds orders a ab; set_sds inventory a ab           # (2)
sleep 5; set_sds inventory b ab                                # (3)
sleep 5; set_sds orders b ab
sleep 5; set_sds orders b b; set_sds inventory b b             # (4)
wait $LOAD
grep '^Code' $SDS/fortio.txt

echo "### The same switch, without publishing root B first"
START=$(date +%s.%N)
set_sds orders a a; set_sds inventory a a
sleep 1; set_sds inventory b a                                 # (5)
sleep 1
curl -s -w "\nHTTP %{http_code}\n" http://127.0.0.1:18700/ | fold -w 76
