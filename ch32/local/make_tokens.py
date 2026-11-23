"""Creates a signing key, its public JWKS, and five test tokens in the
format that Keycloak issues for the realm "shop".

Usage: python3 make_tokens.py <output directory> [issuer]
Writes jwks.json and admin.jwt, user.jwt, expired.jwt, forged.jwt,
wrong-issuer.jwt.
"""
import json
import sys
import time
import uuid
from pathlib import Path

import jwt
from cryptography.hazmat.primitives.asymmetric import rsa
from jwt.algorithms import RSAAlgorithm

out = Path(sys.argv[1])
issuer = (sys.argv[2] if len(sys.argv) > 2
          else "https://keycloak.tektutor.test/realms/shop")
out.mkdir(parents=True, exist_ok=True)

key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
other = rsa.generate_private_key(public_exponent=65537, key_size=2048)
kid = "shop-key-1"
public = json.loads(RSAAlgorithm.to_jwk(key.public_key()))
public.update({"kid": kid, "use": "sig", "alg": "RS256"})
(out / "jwks.json").write_text(json.dumps({"keys": [public]}, indent=2))  # (1)


def token(name, roles, signer=key, iss=issuer, lifetime=300):
    now = int(time.time())
    claims = {                                                    # (2)
        "iss": iss,
        "sub": str(uuid.uuid5(uuid.NAMESPACE_DNS, name)),
        "aud": "account",
        "azp": "shop-cli",
        "preferred_username": name,
        "realm_access": {"roles": roles},
        "iat": now,
        "exp": now + lifetime,
    }
    return jwt.encode(claims, signer, algorithm="RS256",
                      headers={"kid": kid, "typ": "JWT"})


tokens = {
    "admin": token("kayal", ["admin", "user"]),
    "user": token("prabhu", ["user"]),
    "expired": token("prabhu", ["user"], lifetime=-300),            # (3)
    "forged": token("prabhu", ["admin"], signer=other),             # (4)
    "wrong-issuer": token("prabhu", ["user"], iss="https://evil.example"),
}
for name, value in tokens.items():
    (out / f"{name}.jwt").write_text(value)
print(f"wrote jwks.json and {len(tokens)} tokens to {out}")
