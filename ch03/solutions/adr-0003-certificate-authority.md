# ADR-0003: Certificate authority for the TekTutor Shop meshes

Date: 2026-10-13
Status: Accepted
Deciders: security engineer, platform team lead
Review by: 2027-04-30

## Context
The company runs a corporate PKI with an offline root CA, operated by
one security engineer. We run two meshes (ADR-0002) and plan a second
region. Auditors want proof of encryption and of key protection.

## Options considered
1. Self-signed istiod root: no work today; the root key lives in a
   Kubernetes secret and expires in ten years with no owner.
2. Plugged-in intermediate CA per mesh, signed by the corporate root:
   one signing ceremony per mesh; root key stays offline.
3. cert-manager with istio-csr: flexible, but adds a component that
   the platform team does not run today.
4. SPIRE: strongest attestation; too much new software for two
   engineers.

## Decision
We will use option 2, because it keeps the root key offline and uses
the PKI process the security team already runs.

## Consequences
- Easier: audit evidence for key protection; both regions share the
  corporate root, so cross-region trust is simple.
- Note: a shared root means each mesh can verify the other's
  certificates. Separation between the meshes comes from trust domains
  and authorization policy, not from the CA (see ADR-0002).
- Harder: intermediate rotation is a manual ceremony.
- We must: rotate each intermediate every 12 months, owned by the
  security engineer, with the runbook in Chapter 29.
- Review early if: the number of meshes grows beyond four.
