"""Issues a workload certificate the way istiod does, from an
intermediate CA made by make-intermediate.sh. It writes the private key,
and the certificate chain: workload, intermediate and root.

Usage: python3 issue_workload_cert.py <ca dir> <namespace> <service account>
                                      [hours] [trust domain]
       example: python3 issue_workload_cert.py ca-out/lab shop orders
"""
import datetime
import sys
from pathlib import Path

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import ExtendedKeyUsageOID

ca_dir, ns, sa = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
hours = float(sys.argv[4]) if len(sys.argv) > 4 else 24.0
trust_domain = sys.argv[5] if len(sys.argv) > 5 else "cluster.local"

ca_cert = x509.load_pem_x509_certificate((ca_dir / "ca-cert.pem").read_bytes())
ca_key = serialization.load_pem_private_key(
    (ca_dir / "ca-key.pem").read_bytes(), password=None)

key = rsa.generate_private_key(public_exponent=65537, key_size=2048)  # (1)
spiffe_id = f"spiffe://{trust_domain}/ns/{ns}/sa/{sa}"                 # (2)
now = datetime.datetime.now(datetime.timezone.utc)

cert = (
    x509.CertificateBuilder()
    .subject_name(x509.Name([]))                                       # (3)
    .issuer_name(ca_cert.subject)
    .public_key(key.public_key())
    .serial_number(x509.random_serial_number())
    .not_valid_before(now - datetime.timedelta(minutes=2))             # (4)
    .not_valid_after(now + datetime.timedelta(hours=hours))
    .add_extension(x509.SubjectAlternativeName(
        [x509.UniformResourceIdentifier(spiffe_id)]), critical=True)
    .add_extension(x509.KeyUsage(
        digital_signature=True, key_encipherment=True,
        content_commitment=False, data_encipherment=False,
        key_agreement=False, key_cert_sign=False, crl_sign=False,
        encipher_only=False, decipher_only=False), critical=True)
    .add_extension(x509.ExtendedKeyUsage(
        [ExtendedKeyUsageOID.SERVER_AUTH, ExtendedKeyUsageOID.CLIENT_AUTH]),
        critical=False)
    .add_extension(x509.BasicConstraints(ca=False, path_length=None),
                   critical=True)
    .sign(ca_key, hashes.SHA256())
)

out = ca_dir / f"{ns}-{sa}"
out.mkdir(exist_ok=True)
(out / "key.pem").write_bytes(key.private_bytes(
    serialization.Encoding.PEM, serialization.PrivateFormat.TraditionalOpenSSL,
    serialization.NoEncryption()))
(out / "cert-chain.pem").write_bytes(                                  # (5)
    cert.public_bytes(serialization.Encoding.PEM)
    + (ca_dir / "cert-chain.pem").read_bytes())
print(f"{spiffe_id} -> {out}/cert-chain.pem")
