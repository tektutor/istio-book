# ADR-0101: Sidecars for the capstone release, ambient mode next

Date: 2026-10-16
Status: Accepted
Deciders: platform team, shop team
Review by: 2027-01-16

## Context
The shop has five services and grows. Chapter 45 measured, at 800
requests per second on one path: sidecars 774 ms of CPU per 1,000
requests and 138 MiB of memory; ztunnel only 336 ms and 33 MiB; a
waypoint 742 ms and 100 MiB. The release needs HTTP routes, JWT checks
and HTTP policies, which ambient mode does only with a waypoint.

## Options considered
1. Sidecars: known to the team, all features; most memory per pod.
2. Ambient with a waypoint for shop: less memory, same features; a new
   operating model, and Argo Rollouts needs its Gateway API plugin.
3. Ambient without a waypoint: cheapest; no HTTP features, so it
   cannot meet R1 and R3.

## Decision
We will run the release with sidecars, because the team has operated
them for a year and the release is not the time to learn a new data
plane. We will move shop to ambient with a waypoint after the release.

## Consequences
Memory stays higher until the move. The capstone's ambient overlay is
tested now, so the move is a label change and one restart. Review early
if memory per node passes 70%.
