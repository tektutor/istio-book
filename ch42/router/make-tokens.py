"""Creates the signing key of a test identity provider, the
RequestAuthentication that trusts it, and one JWT per tenant.

Usage: python3 ch42/router/make-tokens.py [directory]  (default: tokens)
Needs: pip install pyjwt cryptography"""
import json
import os
import sys
import time

import jwt
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa

OUT = sys.argv[1] if len(sys.argv) > 1 else "tokens"
HERE = os.path.dirname(os.path.abspath(__file__))
ISSUER = "https://login.tektutor.test"
os.makedirs(OUT, exist_ok=True)

key_file = os.path.join(OUT, "signing-key.pem")
if os.path.exists(key_file):
    with open(key_file, "rb") as f:
        key = serialization.load_pem_private_key(f.read(), password=None)
else:
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    with open(key_file, "wb") as f:
        f.write(key.private_bytes(serialization.Encoding.PEM,
                                  serialization.PrivateFormat.PKCS8,
                                  serialization.NoEncryption()))

jwk = json.loads(jwt.algorithms.RSAAlgorithm.to_jwk(key.public_key()))
jwk.update({"kid": "cells-1", "alg": "RS256", "use": "sig"})     # (1)
jwks = json.dumps({"keys": [jwk]})

with open(os.path.join(OUT, "request-authn.yaml"), "w") as f:
    f.write(f"""apiVersion: security.istio.io/v1
kind: RequestAuthentication
metadata:
  name: cell-router
  namespace: router
spec:
  targetRefs:
  - kind: Gateway
    group: gateway.networking.k8s.io
    name: cell-router
  jwtRules:
  - issuer: {ISSUER}
    jwks: '{jwks}'
    outputClaimToHeaders:
    - header: x-tenant
      claim: tenant
""")                                                           # (2)

with open(os.path.join(HERE, "tenants.txt")) as f:
    tenants = [line.split()[0] for line in f
               if line.strip() and not line.startswith("#")]
for tenant in tenants:
    claims = {"iss": ISSUER, "sub": f"user@{tenant}", "tenant": tenant,
              "iat": int(time.time()),
              "exp": int(time.time()) + 30 * 24 * 3600}       # (3)
    token = jwt.encode(claims, key, algorithm="RS256",
                       headers={"kid": "cells-1"})
    with open(os.path.join(OUT, f"{tenant}.jwt"), "w") as f:
        f.write(token)
print(f"{len(tenants)} tokens and request-authn.yaml written to {OUT}")
