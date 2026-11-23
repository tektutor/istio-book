"""Writes an Envoy configuration with one outbound route, built the way
Istio builds it from a VirtualService and a DestinationRule. Use it to
try timeouts, retries and retry budgets with Envoy alone.

Usage: python3 sidecar_route.py [options] > envoy.json
  --listen PORT       port the "sidecar" listens on          (10000)
  --admin PORT        Envoy admin port                        (9901)
  --upstream PORT     port of the service behind it           (18080)
  --cluster NAME      Istio cluster name
                      (outbound|8080||inventory.shop.svc.cluster.local)
  --timeout DUR       route timeout, VirtualService timeout   (0s = none)
  --attempts N        retries.attempts; -1 = no retries block (-1)
  --per-try DUR       retries.perTryTimeout                   (none)
  --retry-on LIST     retries.retryOn                         (Istio's)
  --budget PERCENT    DestinationRule retryBudget.percent     (none)
  --log FILE          access log file           (/tmp/ch24-access.log)
"""
import argparse
import json
from http import HTTPStatus

ISTIO_RETRY_ON = "connect-failure,refused-stream,unavailable,cancelled"
UNLIMITED = 4294967295                       # Istio's circuit breaker default

p = argparse.ArgumentParser()
p.add_argument("--listen", type=int, default=10000)
p.add_argument("--admin", type=int, default=9901)
p.add_argument("--upstream", type=int, default=18080)
p.add_argument("--cluster",
               default="outbound|8080||inventory.shop.svc.cluster.local")
p.add_argument("--timeout", default="0s")
p.add_argument("--attempts", type=int, default=-1)
p.add_argument("--per-try")
p.add_argument("--retry-on")
p.add_argument("--budget", type=float)
p.add_argument("--log", default="/tmp/ch24-access.log")
a = p.parse_args()


def is_status(word):
    """Istio treats a number in retryOn as a status code if HTTP knows it."""
    try:
        HTTPStatus(int(word))
        return True
    except ValueError:
        return False


def retry_policy():                                              # (1)
    policy = {"num_retries": 2,
              "retry_on": ISTIO_RETRY_ON + ",retriable-status-codes",
              "host_selection_retry_max_attempts": 5,
              "retry_host_predicate": [{
                  "name": "envoy.retry_host_predicates.previous_hosts",
                  "typed_config": {
                      "@type": "type.googleapis.com/envoy.extensions."
                               "retry.host.previous_hosts.v3."
                               "PreviousHostsPredicate"}}]}
    if a.attempts == -1:
        return policy                        # no retries block: the default
    if a.attempts == 0:
        return None                          # attempts: 0 turns retries off
    policy["num_retries"] = a.attempts
    if a.retry_on:                                               # (2)
        parts = [x.strip() for x in a.retry_on.split(",") if x.strip()]
        codes = [int(x) for x in parts if is_status(x)]
        words = [x for x in parts if not is_status(x)]
        policy["retry_on"] = ",".join(words)
        if codes:
            policy["retriable_status_codes"] = codes
            if "retriable-status-codes" not in words:
                policy["retry_on"] += ",retriable-status-codes"
    if a.per_try:
        policy["per_try_timeout"] = a.per_try
    return policy


route = {"cluster": a.cluster, "timeout": a.timeout}            # (3)
rp = retry_policy()
if rp:
    route["retry_policy"] = rp

thresholds = {"max_connections": UNLIMITED, "max_pending_requests": UNLIMITED,
              "max_requests": UNLIMITED, "max_retries": UNLIMITED}
if a.budget is not None:                                         # (4)
    thresholds["retry_budget"] = {"budget_percent": {"value": a.budget},
                                  "min_retry_concurrency": 3}

log_format = ("[%START_TIME%] \"%REQ(:METHOD)% %REQ(:PATH)%\" "
              "%RESPONSE_CODE% %RESPONSE_FLAGS% duration=%DURATION%ms "
              "attempts=%UPSTREAM_REQUEST_ATTEMPT_COUNT%\n")
hcm = {
    "@type": "type.googleapis.com/envoy.extensions.filters.network."
             "http_connection_manager.v3.HttpConnectionManager",
    "stat_prefix": "outbound_0.0.0.0_8080",
    "access_log": [{"name": "envoy.access_loggers.file", "typed_config": {
        "@type": "type.googleapis.com/envoy.extensions.access_loggers."
                 "file.v3.FileAccessLog",
        "path": a.log,
        "log_format": {"text_format_source": {
            "inline_string": log_format}}}}],
    "route_config": {"name": "8080", "virtual_hosts": [{
        "name": "inventory.shop.svc.cluster.local:8080",
        "domains": ["*"],
        "include_request_attempt_count": True,                   # (5)
        "routes": [{"name": "default", "match": {"prefix": "/"},
                    "route": route}]}]},
    "http_filters": [{"name": "envoy.filters.http.router", "typed_config": {
        "@type": "type.googleapis.com/envoy.extensions.filters.http."
                 "router.v3.Router"}}],
}
config = {
    "admin": {"address": {"socket_address": {"address": "127.0.0.1",
                                             "port_value": a.admin}}},
    "static_resources": {
        "listeners": [{"name": "0.0.0.0_8080", "address": {"socket_address": {
            "address": "127.0.0.1", "port_value": a.listen}},
            "filter_chains": [{"filters": [{
                "name": "envoy.filters.network.http_connection_manager",
                "typed_config": hcm}]}]}],
        "clusters": [{
            "name": a.cluster, "type": "STATIC", "connect_timeout": "10s",
            "circuit_breakers": {"thresholds": [thresholds]},
            "load_assignment": {"cluster_name": a.cluster, "endpoints": [{
                "lb_endpoints": [{"endpoint": {"address": {"socket_address": {
                    "address": "127.0.0.1",
                    "port_value": a.upstream}}}}]}]}}],
    },
}
print(json.dumps(config, indent=1))
