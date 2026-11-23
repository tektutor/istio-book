"""Writes the Envoy configuration of a sidecar for one pod of the local
ambient lab, in the shape that istiod gives a sidecar in a mesh with
ambient mode turned on:

  virtualOutbound  port 15001: routes by host, then to each Service's pods,
                   with Istio mutual TLS to sidecars and HBONE to ambient pods
  virtualInbound   port 15006: mutual TLS from other sidecars; with
                   permissive mode also plain text
  connect_terminate, main_internal
                   port 15008: HBONE from ztunnels and waypoints

It reads the pods and Services from the lab's ztunnel configuration,
because istiod builds both from the same Kubernetes objects.

Usage: python3 sidecar.py POD CONFIG CERT_DIR SIDECAR_PODS strict|permissive
       SIDECAR_PODS is a comma-separated list of the pods with sidecars.
"""
import sys

import yaml

# Policies in the configuration carry tags such as !Exact; keep them as text.
yaml.SafeLoader.add_multi_constructor(
    "!", lambda loader, tag, node: None)
pod, config_file, certs, sidecar_list, mode = sys.argv[1:6]
config = yaml.safe_load(open(config_file))
sidecars = set(sidecar_list.split(","))
me = next(w for w in config["workloads"] if w["name"] == pod)

T = "type.googleapis.com/envoy."
HCM = T + "extensions.filters.network.http_connection_manager.v3." \
          "HttpConnectionManager"
ROUTER = {"name": "envoy.filters.http.router",
          "typed_config": {"@type": T + "extensions.filters.http.router.v3."
                                        "Router"}}
TLS_PARAMS = {"tls_minimum_protocol_version": "TLSv1_2"}
CERT = {"certificate_chain": {"filename": f"{certs}/cert.pem"},
        "private_key": {"filename": f"{certs}/key.pem"}}
VALIDATION = {"trusted_ca": {"filename": f"{certs}/root-cert.pem"}}
ACCESS_LOG = [{
    "name": "envoy.access_loggers.file",
    "typed_config": {
        "@type": T + "extensions.access_loggers.file.v3.FileAccessLog",
        "path": "/dev/stdout",
        "log_format": {"text_format_source": {"inline_string":
            "[%START_TIME%] %DOWNSTREAM_LOCAL_ADDRESS% \"%REQ(:METHOD)% "
            "%REQ(:PATH)%\" %RESPONSE_CODE% %RESPONSE_FLAGS% "
            "%UPSTREAM_CLUSTER_RAW% %UPSTREAM_HOST% "
            "tls_peer=%DOWNSTREAM_PEER_URI_SAN% "
            "hbone_peer=%FILTER_STATE(io.istio.peer_principal:PLAIN)%\n"}}}}]


def hcm(prefix, routes):
    return [{"name": "envoy.filters.network.http_connection_manager",
             "typed_config": {"@type": HCM, "stat_prefix": prefix,
                              "access_log": ACCESS_LOG,
                              "route_config": routes,
                              "http_filters": [ROUTER]}}]


def endpoints_of(host):
    """The pods behind a Service, from the workloads' Service lists."""
    key = f"{host.split('.')[1]}/{host}"
    for w in config["workloads"]:
        ports = w.get("services", {}).get(key)
        if ports:
            yield w, ports


INTERNAL_UPSTREAM = {
    "name": "envoy.transport_sockets.internal_upstream",
    "typed_config": {
        "@type": T + "extensions.transport_sockets.internal_upstream.v3."
                     "InternalUpstreamTransport",
        "passthrough_metadata": [{
            "kind": {"host": {}},
            "name": "envoy.filters.listener.original_dst"}],
        "transport_socket": {
            "name": "envoy.transport_sockets.raw_buffer",
            "typed_config": {"@type": T + "extensions.transport_sockets."
                                          "raw_buffer.v3.RawBuffer"}}}}

# Outbound: one cluster per Service port, one virtual host per Service.
clusters, vhosts = [], []
for svc in config["services"]:
    host = svc["hostname"]
    vip = svc["vips"][0].split("/")[1]
    for port in svc["ports"]:
        name = f"outbound|{port}||{host}"
        if port != 9080:                          # one listener: port 9080
            continue
        vhosts.append({"name": f"{host}:{port}",
                       "domains": [host, f"{host}:{port}", svc["name"],
                                   f"{svc['name']}:{port}", vip,
                                   f"{vip}:{port}"],
                       "routes": [{"name": "default", "match": {"prefix": "/"},
                                   "route": {"cluster": name,
                                             "timeout": "0s"}}]})
        eps = list(endpoints_of(host))
        tunnel = any(w["name"] not in sidecars and w["protocol"] == "HBONE"
                     for w, _ in eps)
        lb = []
        for w, ports in eps:
            dest = f"{w['workloadIps'][0]}:{ports[port]}"
            if tunnel:                                  # ambient pod: HBONE
                lb.append({"endpoint": {"address": {"envoy_internal_address": {
                    "server_listener_name": "connect_originate",
                    "endpoint_id": dest}}},
                    "metadata": {"filter_metadata": {
                        "envoy.filters.listener.original_dst": {
                            "local": dest}}}})
            else:                                       # sidecar: mutual TLS
                ip, p = dest.split(":")
                lb.append({"endpoint": {"address": {"socket_address": {
                    "address": ip, "port_value": int(p)}}}})
        c = {"name": name, "connect_timeout": "10s",
             "load_assignment": {"cluster_name": name,
                                 "endpoints": [{"lb_endpoints": lb}]}}
        if tunnel:
            c["transport_socket"] = INTERNAL_UPSTREAM
        else:
            c["transport_socket"] = {"name": "tls", "typed_config": {
                "@type": T + "extensions.transport_sockets.tls.v3."
                             "UpstreamTlsContext",
                "common_tls_context": {"alpn_protocols": ["istio"],
                                       "tls_params": TLS_PARAMS,
                                       "tls_certificates": [CERT],
                                       "validation_context": VALIDATION}}}
        clusters.append(c)

original_dst = {"name": "envoy.filters.listener.original_dst",
                "typed_config": {"@type": T + "extensions.filters.listener."
                                              "original_dst.v3.OriginalDst"}}
passthrough = {"name": "PassthroughFilterChain", "filters": [{
    "name": "envoy.filters.network.tcp_proxy",
    "typed_config": {"@type": T + "extensions.filters.network.tcp_proxy.v3."
                                  "TcpProxy",
                     "stat_prefix": "PassthroughCluster",
                     "cluster": "PassthroughCluster"}}]}
app = {"virtual_hosts": [{"name": "inbound|http|9080", "domains": ["*"],
                          "routes": [{"name": "default",
                                      "match": {"prefix": "/"},
                                      "route": {"cluster": "inbound|9080||",
                                                "timeout": "0s"}}]}]}

# Inbound from other sidecars: mutual TLS, and plain text if permissive.
inbound_chains = [{
    "name": "0.0.0.0_9080_mtls",
    "filter_chain_match": {"destination_port": 9080,
                           "transport_protocol": "tls"},
    "transport_socket": {"name": "tls", "typed_config": {
        "@type": T + "extensions.transport_sockets.tls.v3."
                     "DownstreamTlsContext",
        "require_client_certificate": True,
        "common_tls_context": {"tls_params": TLS_PARAMS,
                               "tls_certificates": [CERT],
                               "validation_context": VALIDATION}}},
    "filters": hcm("inbound_0.0.0.0_9080", app)}]
if mode == "permissive":
    inbound_chains.append({
        "name": "0.0.0.0_9080_plaintext",
        "filter_chain_match": {"destination_port": 9080,
                               "transport_protocol": "raw_buffer"},
        "filters": hcm("inbound_0.0.0.0_9080", app)})

listeners = [
    {"name": "virtualOutbound",
     "address": {"socket_address": {"address": "0.0.0.0",
                                    "port_value": 15001}},
     "listener_filters": [original_dst],
     "filter_chains": [{"name": "0.0.0.0_9080",
                        "filter_chain_match": {"destination_port": 9080},
                        "filters": hcm("outbound_0.0.0.0_9080",
                                       {"virtual_hosts": vhosts})}],
     "default_filter_chain": passthrough},
    {"name": "virtualInbound",
     "address": {"socket_address": {"address": "0.0.0.0",
                                    "port_value": 15006}},
     "access_log": [{                         # connections no chain accepts
         "name": "envoy.access_loggers.file",
         "typed_config": {
             "@type": T + "extensions.access_loggers.file.v3.FileAccessLog",
             "path": "/dev/stdout",
             "log_format": {"text_format_source": {"inline_string":
                 "[%START_TIME%] %DOWNSTREAM_LOCAL_ADDRESS% %RESPONSE_FLAGS% "
                 "%RESPONSE_CODE_DETAILS% from "
                 "%DOWNSTREAM_REMOTE_ADDRESS%\n"}}}}],
     "listener_filters": [original_dst, {
         "name": "envoy.filters.listener.tls_inspector",
         "typed_config": {"@type": T + "extensions.filters.listener."
                                       "tls_inspector.v3.TlsInspector"}}],
     "filter_chains": inbound_chains},
    {"name": "connect_terminate",
     "address": {"socket_address": {"address": "0.0.0.0",
                                    "port_value": 15008}},
     "filter_chains": [{
         "transport_socket": {"name": "tls", "typed_config": {
             "@type": T + "extensions.transport_sockets.tls.v3."
                          "DownstreamTlsContext",
             "require_client_certificate": True,
             "common_tls_context": {
                 "alpn_protocols": ["h2"],
                 "tls_params": {"tls_minimum_protocol_version": "TLSv1_3",
                                "tls_maximum_protocol_version": "TLSv1_3"},
                 "tls_certificates": [CERT],
                 "validation_context": VALIDATION}}},
         "filters": [{"name": "envoy.filters.network.http_connection_manager",
                      "typed_config": {
                          "@type": HCM, "stat_prefix": "connect_terminate",
                          "http2_protocol_options": {"allow_connect": True},
                          "upgrade_configs": [{"upgrade_type": "CONNECT"}],
                          "route_config": {"virtual_hosts": [{
                              "name": "default", "domains": ["*"],
                              "routes": [{"match": {"connect_matcher": {}},
                                          "route": {
                                              "cluster": "main_internal",
                                              "upgrade_configs": [{
                                                  "upgrade_type": "CONNECT",
                                                  "connect_config": {}}]}}]}]},
                          "http_filters": [{
                              "name": "connect_authority",
                              "typed_config": {
                                  "@type": T + "extensions.filters.http."
                                               "set_filter_state.v3.Config",
                                  "on_request_headers": [{
                                      "object_key": "envoy.filters.listener."
                                                    "original_dst.local_ip",
                                      "format_string": {"text_format_source": {
                                          "inline_string":
                                              "%REQ(:AUTHORITY)%"}},
                                      "shared_with_upstream": "ONCE"}, {
                                      "object_key": "io.istio.peer_principal",
                                      "factory_key": "envoy.string",
                                      "format_string": {"text_format_source": {
                                          "inline_string":
                                              "%DOWNSTREAM_PEER_URI_SAN%"}},
                                      "shared_with_upstream": "ONCE"}]}},
                              ROUTER]}}]}]},
    {"name": "main_internal", "internal_listener": {},
     "listener_filters": [original_dst],
     "filter_chains": [{"name": "inbound_hbone_9080",
                        "filter_chain_match": {"destination_port": 9080},
                        "filters": hcm("inbound_hbone_9080", app)}]},
    {"name": "connect_originate", "internal_listener": {},
     "listener_filters": [original_dst],
     "filter_chains": [{"filters": [{
         "name": "envoy.filters.network.tcp_proxy",
         "typed_config": {"@type": T + "extensions.filters.network.tcp_proxy."
                                       "v3.TcpProxy",
                          "stat_prefix": "connect_originate",
                          "cluster": "connect_originate",
                          "tunneling_config": {
                              "hostname": "%DOWNSTREAM_LOCAL_ADDRESS%"}}}]}]},
]

clusters += [
    {"name": "inbound|9080||", "connect_timeout": "10s",
     "load_assignment": {"cluster_name": "inbound|9080||", "endpoints": [{
         "lb_endpoints": [{"endpoint": {"address": {"socket_address": {
             "address": "127.0.0.1", "port_value": 9080}}}}]}]}},
    {"name": "main_internal", "transport_socket": INTERNAL_UPSTREAM,
     "load_assignment": {"cluster_name": "main_internal", "endpoints": [{
         "lb_endpoints": [{"endpoint": {"address": {"envoy_internal_address": {
             "server_listener_name": "main_internal"}}}}]}]}},
    {"name": "connect_originate", "type": "ORIGINAL_DST",
     "lb_policy": "CLUSTER_PROVIDED", "connect_timeout": "10s",
     "original_dst_lb_config": {"upstream_port_override": 15008},
     "typed_extension_protocol_options": {
         "envoy.extensions.upstreams.http.v3.HttpProtocolOptions": {
             "@type": T + "extensions.upstreams.http.v3.HttpProtocolOptions",
             "explicit_http_config": {"http2_protocol_options": {}}}},
     "transport_socket": {"name": "tls", "typed_config": {
         "@type": T + "extensions.transport_sockets.tls.v3."
                      "UpstreamTlsContext",
         "common_tls_context": {
             "alpn_protocols": ["h2"],
             "tls_params": {"tls_minimum_protocol_version": "TLSv1_3",
                            "tls_maximum_protocol_version": "TLSv1_3"},
             "tls_certificates": [CERT],
             "validation_context": VALIDATION}}}},
    {"name": "PassthroughCluster", "type": "ORIGINAL_DST",
     "lb_policy": "CLUSTER_PROVIDED", "connect_timeout": "10s"},
]

ip = me["workloadIps"][0]
yaml.safe_dump({
    "node": {"id": f"sidecar~{ip}~{pod}.bookinfo~bookinfo.svc.cluster.local",
             "cluster": f"{me['canonicalName']}.bookinfo"},
    "bootstrap_extensions": [{
        "name": "envoy.bootstrap.internal_listener",
        "typed_config": {"@type": T + "extensions.bootstrap."
                                      "internal_listener.v3.InternalListener"}}],
    "static_resources": {"listeners": listeners, "clusters": clusters},
    "admin": {"address": {"socket_address": {"address": "127.0.0.1",
                                             "port_value": 15000}}},
}, sys.stdout, sort_keys=False)
