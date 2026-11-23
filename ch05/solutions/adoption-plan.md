# Lab 5.2 solution: adoption plan for a 40-team organisation

One good answer. Compare your reasons with mine.

## 1. Adoption plan (nine months)

| Month | Phase | Scope | Exit test |
| --- | --- | --- | --- |
| 1 | Preparation | Install Istio in dev; RACI signed; golden path script; runbooks for the five common problems; guardrails installed in dev | RACI reviewed by all four teams; guardrail tests pass |
| 2 | Pilot | Three pilot teams in dev and staging run all four phases | Pilot teams can onboard a service in under one hour without help |
| 3 | Phase 1: observe | All production namespaces enrolled, PERMISSIVE | Dashboards used in at least two incident reviews |
| 4 to 6 | Phase 2: encrypt | STRICT mTLS, about 30 namespaces a month, lowest-risk first | mTLS metric at 100 percent for two weeks per namespace |
| 6 | Audit finding closed | Evidence script output for all production namespaces | Evidence script: mesh-wide STRICT, no unexplained exceptions |
| 6 to 8 | Phase 3: control traffic | Timeouts on every route through the golden path; retry ownership moved to the mesh | No timeout warnings in the audit log for 30 days |
| 7 to 9 | Phase 4: authorize | Deny by default, sensitive namespaces first, dry-run before deny | Every namespace has an allow list |

### Pilot teams

- The checkout team: a Go service with a strong on-call culture, and an
  important business path that will show value quickly.
- One Spring Boot team that already uses Resilience4j: it shows how to move
  retries from code to the mesh without retrying twice.
- One team that asked for the mesh: motivated teams finish pilots.

### Teams that already retry in code

During phase 3, each team chooses one retry layer per call. Generic retry
loops move to the mesh. Resilience4j stays where it holds business
knowledge: fallbacks, bulkheads around slow dependencies, and circuit
breakers with business-specific thresholds. The golden path sets mesh
retries to zero for routes whose callers keep code retries, and the team
records the choice in its service README.

## 2. RACI additions

| Activity | Platform | App team | Security | SRE |
| --- | --- | --- | --- | --- |
| Approving an mTLS exception label | R | C | A | I |
| Monthly evidence report to the auditors | R | I | A | I |
| Golden path changes and new defaults | A, R | C | C | C |

## 3. Guardrails before phase 2

| Guardrail | Action |
| --- | --- |
| EnvoyFilter only in istio-system | Deny |
| Gateways only in approved namespaces (waypoints allowed) | Deny |
| No PERMISSIVE or DISABLE without an exception label | Deny (from phase 2) |
| Every VirtualService route has a timeout | Warn, Audit |
| Every HTTPRoute rule has `timeouts.request` | Warn, Audit |
| AuthorizationPolicy with an empty `from` in production | Warn, Audit |

## Answers to the check questions

1. Yes. The added rows each have one A.
2. Yes. The finding closes when the evidence script reports mesh-wide STRICT
   with only recorded exceptions, in month 6.
3. The SRE on call, using the runbook for the matching symptom, with the
   platform team as second line for control plane and ztunnel problems.
4. Monthly: share of namespaces per phase, mTLS share, golden path share,
   support questions per team. Pause the rollout if any mesh-caused
   production incident has no runbook, or if support questions per team
   rise two months in a row.
