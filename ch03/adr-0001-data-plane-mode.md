# ADR-0001: Data plane mode for TekTutor Shop

Date: 2026-10-13
Status: Accepted
Deciders: platform team lead, orders and inventory tech leads, SRE lead
Review by: 2027-04-30

## Context
TekTutor Shop runs 38 services in 4 namespaces on one OpenShift cluster.
Most services need mTLS and L4 authorization only. The checkout path
(6 services) needs retries, timeouts and header-based canary routing.
The platform team has two engineers. A sidecar upgrade today restarts
every pod, and the business allows one maintenance window per month.
We run OpenShift Service Mesh 3.4, where ztunnel and waypoints are GA.

## Options considered
1. Sidecar mode everywhere: the most mature, and every Envoy feature is
   available. Costs one proxy per pod and a restart of every pod on each
   mesh upgrade.
2. Ambient mode everywhere: lowest resource cost, no restarts for
   ztunnel upgrades. Needs waypoints for L7 features, and the team has
   no ambient experience yet.
3. Ambient mode by default, waypoints for the checkout namespace only.

## Decision
We will use option 3, because only 6 of 38 services need L7 features,
and removing pod restarts from mesh upgrades lets us patch every month.

## Consequences
- Easier: mesh upgrades without pod restarts; lower proxy cost.
- Harder: long-lived connections on a node reconnect during a ztunnel
  upgrade, so every client must handle reconnects.
- Harder: L7 policy must use Gateway API and targetRefs, not selectors.
- We must: run the sidecar-to-ambient plan in Chapter 37 for checkout,
  and add waypoint metrics to the SRE dashboards.
- Review early if: we need EnvoyFilter or per-pod Wasm in many services.
