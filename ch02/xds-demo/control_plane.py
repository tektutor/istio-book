"""A tiny xDS control plane for one Envoy proxy.

Envoy polls it over REST for its listeners (LDS) and clusters (CDS).
It always answers with the same configuration: a listener on port 10000
that sends every HTTP request to the inventory service on port 8081.
Istio's istiod does the same job over gRPC, for thousands of proxies.
"""
import json
import signal
from http.server import BaseHTTPRequestHandler, HTTPServer

VERSION = "v1"
API = "type.googleapis.com/envoy."
LISTENER_TYPE = API + "config.listener.v3.Listener"
CLUSTER_TYPE = API + "config.cluster.v3.Cluster"
HCM_TYPE = (API + "extensions.filters.network.http_connection_manager"
            ".v3.HttpConnectionManager")
ROUTER_TYPE = API + "extensions.filters.http.router.v3.Router"


def address(port):
    return {"socket_address": {"address": "127.0.0.1", "port_value": port}}


LISTENER = {
    "@type": LISTENER_TYPE,
    "name": "shop_http",
    "address": address(10000),
    "filter_chains": [{"filters": [{
        "name": "envoy.filters.network.http_connection_manager",
        "typed_config": {
            "@type": HCM_TYPE,
            "stat_prefix": "shop",
            "route_config": {
                "name": "shop_routes",
                "virtual_hosts": [{
                    "name": "all",
                    "domains": ["*"],
                    "routes": [{
                        "match": {"prefix": "/"},
                        "route": {"cluster": "inventory", "timeout": "2s"},
                    }],
                }],
            },
            "http_filters": [{
                "name": "envoy.filters.http.router",
                "typed_config": {"@type": ROUTER_TYPE},
            }],
        },
    }]}],
}

CLUSTER = {
    "@type": CLUSTER_TYPE,
    "name": "inventory",
    "type": "STATIC",
    "connect_timeout": "1s",
    "load_assignment": {
        "cluster_name": "inventory",
        "endpoints": [{"lb_endpoints": [
            {"endpoint": {"address": address(8081)}},
        ]}],
    },
}

# Each REST path serves one resource type.
RESOURCES = {
    "/v3/discovery:listeners": (LISTENER_TYPE, LISTENER),
    "/v3/discovery:clusters": (CLUSTER_TYPE, CLUSTER),
}


class XDSHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        request = json.loads(self.rfile.read(length) or b"{}")
        if self.path not in RESOURCES:
            self.send_error(404)
            return
        type_url, resource = RESOURCES[self.path]
        if request.get("version_info") == VERSION:
            self.send_response(304)          # Envoy already has this version
            self.end_headers()
            return
        body = json.dumps({"version_info": VERSION, "type_url": type_url,
                           "resources": [resource]}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
        kind = self.path.split(":")[1]
        print(f"sent {kind} version {VERSION}", flush=True)

    def log_message(self, *args):            # keep the output short
        pass


def stop(signum, frame):
    raise KeyboardInterrupt                  # treat SIGTERM like Ctrl+C


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, stop)
    print("control plane listening on 127.0.0.1:18000", flush=True)
    try:
        HTTPServer(("127.0.0.1", 18000), XDSHandler).serve_forever()
    except KeyboardInterrupt:                # Ctrl+C stops the control plane
        print("control plane stopped", flush=True)
