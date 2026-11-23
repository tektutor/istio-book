#!/usr/bin/env bash
# Decodes a test token, then sends eight requests to the orders sidecar
# with JWT validation, a CUSTOM policy that asks OPA, and ALLOW rules.
# You need Envoy, OPA with the Envoy plugin (as "opa"), and python3 with
# pyjwt and cryptography.
#
# Usage: ch32/local/jwt-demo.sh       (from the repository root)
set -uo pipefail

TOK=/tmp/ch32-tokens
python3 ch32/local/make_tokens.py $TOK > /dev/null
opa run --server --addr 127.0.0.1:18181 --log-level error \
  --config-file ch32/local/opa-config.yaml ch32/opa/policy.rego \
  > /tmp/ch32-opa.log 2>&1 &
OPA=$!
envoy -c ch32/local/jwt-envoy.yaml --base-id 65 --log-level error \
  > /tmp/ch32-envoy.log 2>&1 &
ENVOY=$!
trap 'kill $ENVOY $OPA 2>/dev/null' EXIT
until curl -s http://127.0.0.1:19934/ready 2>/dev/null | grep -q LIVE &&
      curl -s http://127.0.0.1:18181/health > /dev/null
do kill -0 $ENVOY $OPA || exit 1; sleep 0.2; done

echo "### The user token, decoded"                             # (1)
python3 - $TOK/user.jwt <<'PY'
import base64, json, sys
parts = open(sys.argv[1]).read().strip().split(".")
for name, part in zip(["header", "payload"], parts[:2]):
    data = json.loads(base64.urlsafe_b64decode(part + "=" * (-len(part) % 4)))
    print(name + ":")
    for k, v in data.items():
        print(f"  {k}: {json.dumps(v)}")
print("signature:", parts[2][:24] + "...", f"({len(parts[2])} characters)")
PY

call() {                       # call <token or -> <path>
  local auth=()
  [ "$1" != - ] && auth=(-H "Authorization: Bearer $(cat $TOK/$1.jwt)")
  printf "%-13s %-26s -> " "$1" "$2"
  curl -s -o /tmp/ch32-body.txt -D /tmp/ch32-head.txt -w "%{http_code}" \
    "${auth[@]}" "http://127.0.0.1:18960$2"
  echo " $(head -c 34 /tmp/ch32-body.txt)" \
    "$(grep -i '^x-app-saw-user' /tmp/ch32-head.txt | tr -d '\r')"
}
echo "### Eight requests"
call -            /api/orders/7                                # (2)
call forged       /api/orders/7
call expired      /api/orders/7
call wrong-issuer /api/orders/7
call user         /api/orders/7                                # (3)
call user         /api/admin/stats
call admin        /api/admin/stats
call user         "/api/orders/7?amount=1500"                  # (4)
echo "### OPA's decisions"
grep -o '"result":[a-z]*' /tmp/ch32-opa.log | sort | uniq -c   # (5)
