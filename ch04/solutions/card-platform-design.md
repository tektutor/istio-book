# Lab 4.1 solution: card-payment platform design

This is one good answer, not the only one. Compare the reasons for each
boundary with yours.

## 1. One-page design

### Clusters and meshes

| Data centre | Cluster | Mesh | Workloads |
| --- | --- | --- | --- |
| DC1 | ocp-dc1-apps | mesh `apps`, trust domain `apps.bank.example` | 54 non-CDE services |
| DC2 | ocp-dc2-apps | mesh `apps` (same mesh, multi-primary) | 54 non-CDE services |
| DC1 | ocp-dc1-cde | mesh `cde`, trust domain `cde.bank.example` | 6 CDE services |
| DC2 | ocp-dc2-cde | mesh `cde` (same mesh, multi-primary) | 6 CDE services |

- Two meshes, each spanning both data centres with the multi-primary model.
  Reason: the CDE needs a hard boundary that the QSA can test, and the
  business needs to survive the loss of one data centre.
- Four clusters, not two. Reason: a separate CDE cluster keeps non-CDE
  nodes, operators and administrators out of PCI scope. Agree this with the
  QSA before building.
- The CDE mesh runs in sidecar mode: six services, every Envoy control at
  the pod, and `REGISTRY_ONLY` enforced. The apps mesh runs in ambient mode
  with waypoints for the services that need layer 7 features.

### Gateways

- Public and partner traffic: CDN and WAF, then the bank's API gateway
  (API keys, partner quotas), then the Istio ingress gateway of the apps
  mesh. Partner JWTs are validated once, at the API gateway. TLS for
  external clients ends at the API gateway; the API gateway opens new TLS
  to the ingress gateway.
- Apps mesh to CDE mesh: east-west gateways. The CDE gateway accepts only
  the identities that call CDE APIs: the checkout and refund services.
- CDE egress: an egress gateway in the CDE mesh with two ServiceEntries,
  the card network API and the partner bank's file endpoint. Nothing else.

### Certificates

- Corporate offline root CA, in the HSM.
- Four intermediates, one per cluster, issued by the root and plugged into
  each istiod. Two-year lifetime, rotated by the security team, tracked in
  the PKI inventory.
- Workload certificates: 24 hours (the Istio default), issued by istiod.
- Each mesh trusts the other mesh's trust domain only at the east-west
  gateways, through the shared root and explicit AuthorizationPolicy.

### Failover

- GSLB in front of the API gateway in both data centres, with health checks
  on the ingress gateways.
- Locality-aware routing with outlier detection in every DestinationRule
  that serves CDE APIs, so calls stay in their own data centre and fail
  over within seconds when local endpoints fail.
- Database replication is out of the mesh's scope. The 15-minute target
  depends on the database design, which needs its own ADR.

## 2. Compliance mapping

| Control | Mesh feature | Evidence | Not covered by the mesh (owner) |
| --- | --- | --- | --- |
| PCI 1 | Separate CDE mesh; deny-by-default AuthorizationPolicy; egress gateway with two ServiceEntries | Monthly evidence script output; policy YAML in Git | Data-centre firewalls, network diagrams (network team) |
| PCI 4 | TLS origination to the card network at the egress gateway; mesh certificates in the 4.2.1.1 inventory | Egress gateway config; `istioctl proxy-config secret` export | All non-mesh certificates; HSM keys (security team) |
| PCI 7 | One ALLOW rule per caller, method and path for each CDE service | Policy YAML; test results that show denied calls | Human access to CDE data (application and DBA teams) |
| PCI 8 | Workload identity on every call (supporting evidence) | PeerAuthentication STRICT; mTLS metrics | User and administrator authentication (identity team) |
| PCI 10 | JSON access logs for every request, sent to the SIEM | SIEM retention report; sample log lines | Log review, alerting, retention (SOC) |
| SM-DR6 | STRICT mTLS; sidecars on loopback | Evidence script; tcpdump test record | None |
| SM-DR8 | `REGISTRY_ONLY` in the CDE mesh | istiod config export; blocked-call test | Apps mesh egress in ambient mode: NetworkPolicy (platform team) |
| SM-DR12 | Plugged-in intermediates from the corporate root | CA chain export | Root CA ceremony (security team) |
| SM-DR13 | 24-hour workload certificates | `proxy-config secret` showing expiry | None |
| SM-DR22 | Access logs with identity and trace ID; tokens not logged | Telemetry resource; log format review | Masking in application logs (application teams) |

## Answers to the check questions

1. No. Only checkout and refund identities are allowed through the CDE
   east-west gateway, and each CDE service has its own allow list. Proof:
   the evidence script, the policy files in Git, and a test run that shows
   a denied call from another service, repeated every quarter.
2. Outlier detection in the caller's proxy ejects the failed endpoints and
   locality failover sends calls to the other data centre within seconds.
   For new user sessions, the GSLB health check removes the failed data
   centre within its check interval.
3. TLS ends at the API gateway, which validates partner JWTs. The ingress
   gateway does not validate them again. Inside the mesh, services that
   need user claims check them with RequestAuthentication.
4. The root and four intermediates (security team, two years), the ingress
   and egress gateway certificates (platform team, 90 days with
   cert-manager), and the workload certificates (istiod, 24 hours).
