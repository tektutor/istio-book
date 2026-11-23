"""Shows how a sidecar's memory and config size grow with the number of
services it knows about. It writes an Envoy config with the outbound
clusters and routes that Istio would send for N services, starts Envoy
with it, and reads Envoy's own figures.

Usage: python3 scope-demo.py [N ...]        (default: 20 200 2000)
You need Envoy on your PATH. Ports 19950 and 18950 must be free.
"""
import json
import subprocess
import sys
import time
import urllib.request

ADMIN = 19950


def service_config(i):
    """One Kubernetes Service in Istio's shape: a cluster with three
    endpoints, and a virtual host with the names a client may use."""
    name = f"svc-{i:04d}.team-{i % 50:02d}.svc.cluster.local"
    short, ns = name.split(".")[0], name.split(".")[1]
    cluster = {
        "name": f"outbound|8080||{name}",
        "type": "STATIC",
        "connect_timeout": "10s",
        "lb_policy": "LEAST_REQUEST",
        "circuit_breakers": {"thresholds": [{
            "max_connections": 4294967295, "max_pending_requests": 4294967295,
            "max_requests": 4294967295, "max_retries": 4294967295}]},
        "load_assignment": {"cluster_name": name, "endpoints": [{
            "lb_endpoints": [{"endpoint": {"address": {"socket_address": {
                "address": f"10.{i // 250}.{i % 250}.{e}",
                "port_value": 8080}}}} for e in (1, 2, 3)]}]},
    }
    vhost = {
        "name": f"{name}:8080",
        "domains": [name, f"{short}.{ns}.svc", f"{short}.{ns}",
                    f"10.96.{i // 250}.{i % 250}"],
        "routes": [{"name": "default", "match": {"prefix": "/"},
                    "route": {"cluster": f"outbound|8080||{name}",
                              "timeout": "0s",
                              "retry_policy": {
                                  "retry_on": "connect-failure,refused-stream,"
                                              "unavailable,cancelled,"
                                              "retriable-status-codes",
                                  "num_retries": 2}}}],
    }
    return cluster, vhost


def envoy_config(n):
    clusters, vhosts = zip(*(service_config(i) for i in range(n)))
    hcm = {
        "@type": "type.googleapis.com/envoy.extensions.filters.network."
                 "http_connection_manager.v3.HttpConnectionManager",
        "stat_prefix": "outbound_0.0.0.0_8080",
        "route_config": {"name": "8080", "virtual_hosts": list(vhosts)},
        "http_filters": [{"name": "envoy.filters.http.router",
                          "typed_config": {
                              "@type": "type.googleapis.com/envoy.extensions."
                                       "filters.http.router.v3.Router"}}],
    }
    return {
        "admin": {"address": {"socket_address": {
            "address": "127.0.0.1", "port_value": ADMIN}}},
        "static_resources": {
            "listeners": [{"name": "0.0.0.0_8080", "address": {
                "socket_address": {"address": "127.0.0.1",
                                   "port_value": 18950}},
                "filter_chains": [{"filters": [{
                    "name": "envoy.filters.network.http_connection_manager",
                    "typed_config": hcm}]}]}],
            "clusters": list(clusters)},
    }


def admin(path):
    with urllib.request.urlopen(f"http://127.0.0.1:{ADMIN}{path}",
                                timeout=5) as r:
        return r.read()


def measure(n):
    path = f"/tmp/ch23-envoy-{n}.json"
    with open(path, "w") as f:
        json.dump(envoy_config(n), f)
    start = time.monotonic()
    proc = subprocess.Popen(["envoy", "-c", path, "--base-id", "48",
                             "--log-level", "error"],
                            stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL)
    try:
        while True:                                            # (1)
            try:
                if admin("/ready").strip() == b"LIVE":
                    break
            except OSError:
                pass
            time.sleep(0.05)
        ready = time.monotonic() - start
        time.sleep(1)
        memory = json.loads(admin("/memory"))                  # (2)
        dump = len(admin("/config_dump"))                      # (3)
    finally:
        proc.terminate()
        proc.wait()
    return ready, int(memory["allocated"]), dump


print(f"{'services':>8} {'ready':>8} {'memory':>10} {'config dump':>12}")
for n in [int(a) for a in sys.argv[1:]] or [20, 200, 2000]:
    ready, allocated, dump = measure(n)
    print(f"{n:>8} {ready:>7.2f}s {allocated / 2**20:>7.1f} MiB "
          f"{dump / 2**20:>8.2f} MiB")
