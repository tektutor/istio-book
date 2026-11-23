# Capstone design: TekTutor Shop 2.0 on the mesh

Author: TekTutor platform team   Date: 2026-10-16   Version: 1

## 1. Goal
Release inventory 1.1 to all customers without a maintenance window, and
leave the shop with mutual TLS everywhere, tokens checked at the edge,
traces for slow requests and policies that a pipeline tests.

## 2. Requirements and how each is checked
- R1: inventory 1.1 goes out at 10%, 50%, 100%; more than 1% errors on
  the canary rolls it back without help.
  Check: Lab 48.2 with break-canary.sh 5.
- R2: only mutual TLS reaches shop pods.
  Check: the case "legacy/test-plain ... 000" in tests/cases.txt.
- R3: the public gateway's calls to orders carry a valid JWT.
  Check: the gateway case, and one call with a Keycloak token.
- R4: 10% of shop requests traced, end to end.
  Check: one trace with gateway, orders and inventory spans.
- R5: every policy change passes the Chapter 48 pipeline.
  Check: required status checks on main.
- R6: the same requirements in sidecar and ambient mode.
  Check: verify_capstone.py in both modes.
- R7: the release survives istiod going down.
  Check: drill, istiod stopped during the 10% step.

## 3. Picture
browser -> public gateway (JWT passed on) -> orders (JWT checked, R3)
-> inventory stable or canary (weights from Argo Rollouts, R1).
Every hop: mutual TLS (R2), spans (R4). In ambient mode the waypoint of
shop does the HTTP work of the sidecars: routes, JWT, policies.

## 4. Decisions
- ADR-0101: sidecars now, ambient after one quiet month: the team knows
  sidecars, and ambient needs a waypoint for every rule we use.
- ADR-0102: Argo Rollouts: the team runs Argo CD, and OpenShift GitOps
  supports it.
- ADR-0103: check the JWT at orders, not only at the gateway: internal
  callers cannot skip the check.

## 5. Risks and the drill
- A route change cannot reach the proxies while istiod is down: the
  canary stays at its weight. Seen as: Rollout step does not advance.
  Drill: stop istiod during the 10% step (Lab 44.1).
- A canary gets too little traffic to judge: one error is above 1%.
  Seen as: analysis fails on a healthy release. Mitigation: 20 requests
  per second of steady load during the release.

## 6. Out of scope
Multi-cluster failover (Chapter 41), the Java cart service, and VMs.
