#!/usr/bin/env python3
"""Reports how far a migration to the mesh has come, per namespace:
pods with a sidecar or in ambient mode, pods outside the mesh, the mutual
TLS mode, and the number of authorization policies.

    python3 ch49/k8s/mesh_coverage.py
    python3 ch49/k8s/mesh_coverage.py --prometheus http://localhost:9090

With --prometheus, it also prints the share of HTTP requests that each
namespace received over mutual TLS in the last hour. Sidecars and
waypoints report these requests; ztunnel alone reports only TCP metrics,
so an ambient namespace without a waypoint shows "-". Set KUBECTL=oc on
OpenShift, and ROOT_NAMESPACE if the control plane is not in istio-system.
"""
import json
import os
import subprocess
import sys
import urllib.parse
import urllib.request

KUBECTL = os.environ.get("KUBECTL", "kubectl")
ROOT = os.environ.get("ROOT_NAMESPACE", "istio-system")
SKIP = ("kube-", "openshift", "istio-system", "default")


def get(kind):
    out = subprocess.run([KUBECTL, "get", kind, "-A", "-o", "json"],
                         capture_output=True, text=True, check=True).stdout
    return json.loads(out)["items"]


def namespace_labels():
    out = subprocess.run([KUBECTL, "get", "namespaces", "-o", "json"],
                         capture_output=True, text=True, check=True).stdout
    return {n["metadata"]["name"]: n["metadata"].get("labels", {})
            for n in json.loads(out)["items"]}


def data_plane(pod, ns_labels):
    """sidecar, ambient or none, the way the Istio CNI agent decides it."""
    spec = pod["spec"]
    names = [c["name"] for c in spec.get("containers", [])]
    names += [c["name"] for c in spec.get("initContainers", [])]
    if "istio-proxy" in names:                                  # (1)
        return "sidecar"
    mode = pod["metadata"].get("labels", {}).get(
        "istio.io/dataplane-mode", ns_labels.get("istio.io/dataplane-mode"))
    return "ambient" if mode == "ambient" else "none"            # (2)


def mtls_modes():
    """Namespace-wide PeerAuthentication modes, and the mesh-wide one."""
    modes, mesh = {}, "PERMISSIVE"
    for pa in get("peerauthentications.security.istio.io"):
        if pa["spec"].get("selector"):
            continue                       # workload-level: not counted
        mode = pa["spec"].get("mtls", {}).get("mode", "UNSET")
        if mode == "UNSET":
            continue                       # inherits the mesh-wide mode
        if pa["metadata"]["namespace"] == ROOT:
            mesh = mode
        else:
            modes[pa["metadata"]["namespace"]] = mode
    return modes, mesh


def mtls_share(url):
    """Share of requests received over mutual TLS, per namespace."""
    query = ('sum by (destination_workload_namespace) (rate(istio_requests_'
             'total{reporter="destination",connection_security_policy='
             '"mutual_tls"}[1h])) / sum by (destination_workload_namespace) '
             '(rate(istio_requests_total{reporter="destination"}[1h]))')
    q = urllib.parse.urlencode({"query": query})
    with urllib.request.urlopen(f"{url}/api/v1/query?{q}") as r:   # (3)
        rows = json.load(r)["data"]["result"]
    return {row["metric"].get("destination_workload_namespace"):
            float(row["value"][1]) for row in rows}


def main():
    if sys.argv[1:2] == ["--prometheus"] and len(sys.argv) != 3:
        sys.exit("usage: mesh_coverage.py [--prometheus URL]")
    url = sys.argv[2] if sys.argv[1:2] == ["--prometheus"] else None
    labels = namespace_labels()
    modes, mesh_mode = mtls_modes()
    policies = {}
    for ap in get("authorizationpolicies.security.istio.io"):
        ns = ap["metadata"]["namespace"]
        policies[ns] = policies.get(ns, 0) + 1
    counts = {}
    for pod in get("pods"):
        ns = pod["metadata"]["namespace"]
        if ns.startswith(SKIP) or pod["status"].get("phase") in (
                "Succeeded", "Failed"):
            continue
        plane = data_plane(pod, labels.get(ns, {}))
        counts.setdefault(ns, {"sidecar": 0, "ambient": 0, "none": 0})
        counts[ns][plane] += 1
    share = mtls_share(url) if url else {}

    print(f"{'NAMESPACE':<14}{'PODS':>5}{'SIDECAR':>9}{'AMBIENT':>9}"
          f"{'OUTSIDE':>9}  {'MTLS MODE':<11}{'AUTHZ':>6}"
          + ("  MTLS SHARE" if url else ""))
    total = {"sidecar": 0, "ambient": 0, "none": 0}
    strict = with_authz = 0
    for ns in sorted(counts):
        c = counts[ns]
        pods = sum(c.values())
        mode = modes.get(ns, mesh_mode)
        n_ap = policies.get(ns, 0)
        line = (f"{ns:<14}{pods:>5}{c['sidecar']:>9}{c['ambient']:>9}"
                f"{c['none']:>9}  {mode:<11}{n_ap:>6}")
        if url:
            line += (f"  {share[ns]:10.1%}" if ns in share else "         -")
        print(line)
        for k in total:
            total[k] += c[k]
        strict += mode == "STRICT"
        with_authz += n_ap > 0
    pods = sum(total.values())
    meshed = total["sidecar"] + total["ambient"]
    print(f"\npods in the mesh: {meshed} of {pods} "
          f"({meshed / pods:.0%})" if pods else "\nno pods")         # (4)
    print(f"namespaces with STRICT mTLS: {strict} of {len(counts)}")
    print(f"namespaces with authorization policies: {with_authz} "
          f"of {len(counts)}")


if __name__ == "__main__":
    main()
