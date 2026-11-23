# Team rules for mesh configuration in this repository. conftest runs
# them on every YAML file in a pull request; each message in "deny"
# fails the check.
package main

import rego.v1

authz if input.kind == "AuthorizationPolicy"

# Argo CD may supply the namespace, so a file can leave it out.
name := sprintf("%s/%s", [object.get(input.metadata, "namespace", "-"),
    input.metadata.name])

# An ALLOW rule without "from" matches every caller, with or without
# a sidecar, so it opens the workload to the whole cluster.
deny contains msg if {                                          # (1)
    authz
    object.get(input.spec, "action", "ALLOW") == "ALLOW"
    some i, rule in input.spec.rules
    not rule.from
    msg := sprintf("%s: ALLOW rule %d has no 'from'", [name, i])
}

# A wildcard caller means "anyone with an identity".
deny contains msg if {                                          # (2)
    authz
    some rule in input.spec.rules
    some f in rule.from
    some field in ["principals", "namespaces"]
    some value in object.get(f.source, field, [])
    endswith(value, "*")
    msg := sprintf("%s: wildcard %q in %s", [name, value, field])
}

# Policies with rules must select workloads. A namespace-wide policy
# with rules belongs to the platform team, not to a service team.
deny contains msg if {                                          # (3)
    authz
    count(object.get(input.spec, "rules", [])) > 0
    not input.spec.selector
    not input.spec.targetRefs
    not waypoint_only
    msg := sprintf("%s: rules without a selector", [name])
}

# In ambient mode, ztunnel must let the namespace's waypoint reach every
# pod (Chapter 50): a rule whose only callers are the waypoints of the
# policy's own namespace is fine.
waypoint_only if {
    every rule in input.spec.rules {
        not rule.to
        count(rule.from) > 0
        every f in rule.from {
            count(object.get(f.source, "principals", [])) > 0
            every p in f.source.principals {
                endswith(p, sprintf("/ns/%s/sa/waypoint",
                    [input.metadata.namespace]))
            }
        }
    }
}

# A DestinationRule that turns TLS off breaks STRICT mode (Chapter 47).
deny contains msg if {                                          # (4)
    input.kind == "DestinationRule"
    input.spec.trafficPolicy.tls.mode == "DISABLE"
    msg := sprintf("%s: tls mode DISABLE; let auto mTLS choose", [name])
}

# Short host names depend on the namespace of the resource (Chapter 47).
deny contains msg if {                                          # (5)
    input.kind == "VirtualService"
    some host in input.spec.hosts
    not contains(host, ".")
    msg := sprintf("%s: short host %q; write the full name", [name, host])
}
