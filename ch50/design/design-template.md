# Capstone design: TekTutor Shop 2.0 on the mesh

Author: <name>                Date: YYYY-MM-DD          Version: 1

## 1. Goal
One paragraph: what the release changes for customers and for the team.

## 2. Requirements and how each is checked
| Id | Requirement | Check |
| -- | ----------- | ----- |
| R1 | <canary, rollback> | <command or test> |
| R2 | <mutual TLS> | ... |
| R3 | <JWT at the edge> | ... |
| R4 | <tracing> | ... |
| R5 | <tested policies> | ... |
| R6 | <data plane mode> | ... |
| R7 | <failure drill> | ... |

## 3. Picture
The request path from the browser to inventory, with each proxy, and
where each requirement is enforced. One diagram, ten boxes at most.

## 4. Decisions
ADR-0101 data plane mode, ADR-0102 release controller, ADR-0103 where
the JWT is checked. One line each: the decision and the main reason.

## 5. Risks and the drill
The two risks you worry about most, what you will see if each happens,
and the failure from Chapter 44 that you will run during the release.

## 6. Out of scope
What this release does not do, so that nobody expects it.
