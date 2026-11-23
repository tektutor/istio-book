# ADR-0102: Argo Rollouts for progressive delivery

Date: 2026-10-16
Status: Accepted
Deciders: platform team
Review by: 2027-04-16

## Context
R1 needs automatic rollback on the canary's error rate. The cluster runs
Argo CD for all mesh configuration (Chapter 48). Some teams deploy to
OpenShift, where Red Hat ships OpenShift GitOps.

## Options considered
1. Argo Rollouts: a Rollout replaces the Deployment; we write the route
   and the query; supported in OpenShift GitOps.
2. Flagger: keeps the Deployment and writes the routes itself; built-in
   success-rate check; fits Flux, which we do not run.
3. Manual weights (Chapter 18): no controller; a person must watch.

## Decision
We will use Argo Rollouts, because it fits Argo CD and OpenShift GitOps,
and the route stays visible in Git.

## Consequences
Each service needs a stable and a canary Service and a named route. The
analysis query must use "or vector(0)" and measure the canary alone.
In ambient mode we need the Gateway API plugin. Review if we adopt Flux.
