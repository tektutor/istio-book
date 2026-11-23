# ADR-0002: Mesh count and tenancy for TekTutor Shop

Date: 2026-10-13
Status: Accepted
Deciders: platform team lead, security engineer, payments tech lead
Review by: 2027-04-30

## Context
One OpenShift cluster in one region today; a second region is planned
for next year. The payments service handles card data, and the security
team wants it isolated. The platform team has two engineers. Auditors
ask every year for proof that internal traffic is encrypted.

## Options considered
1. One mesh, namespace tenancy: cheapest; payments shares the control
   plane and the root of trust with every other service.
2. One mesh, payments in its own cluster (cluster tenancy): payments
   gets its own nodes and upgrade timing, but shares trust and config.
3. A separate mesh for payments (mesh tenancy): own control plane and
   own intermediate CA; doubles the upgrade and certificate work.

## Decision
We will use option 3, because the card-data boundary must be provable
to auditors. A separate control plane, trust domain and authorization
policy give them one clear line to check.

## Consequences
- Easier: audit scope is limited to the payments mesh.
- Harder: two control planes to upgrade; cross-mesh calls need explicit
  trust and an east-west gateway.
- We must: give payments its own intermediate CA and trust domain, and
  allow only named callers into payments (see ADR-0003).
- Second region: each region will run both meshes; review this record
  before the second region is built.
- Review early if: the platform team cannot keep both meshes current.
