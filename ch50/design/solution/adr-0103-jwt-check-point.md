# ADR-0103: Check end-user tokens at orders

Date: 2026-10-16
Status: Accepted
Deciders: platform team, security team
Review by: 2027-04-16

## Context
R3 needs a valid JWT on every customer request to the orders API.
Requests arrive through the public gateway; internal jobs also call
orders, with their own mesh identity and no user token.

## Options considered
1. At the gateway only: one place; a caller inside the cluster that
   skips the gateway is not checked.
2. At orders: RequestAuthentication and an AuthorizationPolicy that
   requires a token when the caller is the gateway; internal callers
   are allowed by identity.
3. Both: two places to keep in sync, little extra safety.

## Decision
We will check tokens at orders, because the check then holds for every
path to the service, and the policy can tell gateway traffic from
internal traffic by the caller's identity.

## Consequences
The gateway passes the Authorization header on unchanged. In ambient
mode the check moves to the waypoint, with targetRefs. Review if a
second public service needs tokens.
