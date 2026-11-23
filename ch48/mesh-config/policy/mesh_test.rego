# Tests for the rules in mesh.rego: "conftest verify" runs every rule
# whose name starts with test_. Each test gives one input and checks
# the messages that the rules produce for it.
package main

import rego.v1

policy(rules) := {
    "kind": "AuthorizationPolicy",
    "metadata": {"name": "p", "namespace": "shop"},
    "spec": {
        "selector": {"matchLabels": {"app": "inventory"}},
        "rules": rules,
    },
}

test_allow_with_callers_passes if {
    count(deny) == 0 with input as policy([{"from": [{"source": {
        "principals": ["cluster.local/ns/shop/sa/orders"]}}]}])
}

test_rule_without_from_fails if {
    deny["shop/p: ALLOW rule 0 has no 'from'"] with input as policy([{
        "to": [{"operation": {"methods": ["GET"]}}]}])
}

test_deny_rule_without_from_passes if {
    count(deny) == 0 with input as object.union(
        policy([{"to": [{"operation": {"paths": ["/admin/*"]}}]}]),
        {"spec": {"action": "DENY"}},
    )
}

test_wildcard_principal_fails if {
    count(deny) == 1 with input as policy([{"from": [{"source": {
        "principals": ["cluster.local/ns/shop/sa/*"]}}]}])
}

test_allow_nothing_passes if {
    count(deny) == 0 with input as {
        "kind": "AuthorizationPolicy",
        "metadata": {"name": "allow-nothing", "namespace": "shop"},
        "spec": {},
    }
}

test_short_host_fails if {
    count(deny) == 1 with input as {
        "kind": "VirtualService",
        "metadata": {"name": "inventory", "namespace": "shop"},
        "spec": {"hosts": ["inventory"]},
    }
}

test_rule_without_from_fails_without_namespace if {
    count(deny) == 1 with input as {
        "kind": "AuthorizationPolicy",
        "metadata": {"name": "p"},
        "spec": {"rules": [{"to": [{"operation": {"methods": ["GET"]}}]}],
            "selector": {"matchLabels": {"app": "inventory"}}},
    }
}

test_waypoint_rule_without_selector_passes if {
    count(deny) == 0 with input as {
        "kind": "AuthorizationPolicy",
        "metadata": {"name": "allow-waypoint", "namespace": "shop"},
        "spec": {"rules": [{"from": [{"source": {
            "principals": ["cluster.local/ns/shop/sa/waypoint"]}}]}]},
    }
}

test_other_rule_without_selector_fails if {
    count(deny) == 1 with input as {
        "kind": "AuthorizationPolicy",
        "metadata": {"name": "allow-curl", "namespace": "shop"},
        "spec": {"rules": [{"from": [{"source": {
            "principals": ["cluster.local/ns/shop/sa/curl"]}}]}]},
    }
}

test_waypoint_of_other_namespace_fails if {
    count(deny) == 1 with input as {
        "kind": "AuthorizationPolicy",
        "metadata": {"name": "allow-waypoint", "namespace": "shop"},
        "spec": {"rules": [{"from": [{"source": {
            "principals": ["cluster.local/ns/other/sa/waypoint"]}}]}]},
    }
}
