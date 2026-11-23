# Game day plan: <drill name>

Date and time: <date, start, end>     Environment: <cluster, namespace>
Leader: <name>   Operator: <name>   Observer: <name>   Scribe: <name>

## Hypothesis
When <failure>, <service> keeps <SLO>, and the alert <name> fires
within <minutes>.

## Blast radius
Affected: <namespaces, tenants>. Not affected: <the rest>.

## Abort criteria
Stop at once and restore if <user-facing error rate> passes <limit>,
or if anything outside the blast radius changes.

## Steps
| Time | Action | Expected result | Seen |
| --- | --- | --- | --- |
| T+0 | Baseline: load running, all SYNCED | 100% 200 | |
| T+5 | <inject the failure> | <expected> | |
| T+? | Detection: alert fires | within <minutes> | |
| T+? | Runbook: <name> | recovery in <minutes> | |
| T+? | Restore, confirm SYNCED | 100% 200 | |

## Results
Detection time: <minutes>. Recovery time: <minutes>.
What surprised us: <list>.
Actions (owner, date): <list>.
