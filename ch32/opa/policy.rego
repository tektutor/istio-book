# The order limit for the shop: an order request may carry an amount of
# at most 1000. Requests without an amount are allowed.
package istio.authz

default allow := false                                         # (1)

allow if {
	not input.parsed_query.amount                              # (2)
}

allow if {
	to_number(input.parsed_query.amount[0]) <= 1000            # (3)
}
