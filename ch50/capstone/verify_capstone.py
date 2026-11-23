#!/usr/bin/env python3
"""Checks the capstone's configuration in a cluster against the brief.

Each check prints PASS or FAIL with the requirement it belongs to. It
reads the cluster only; the regression tests of Chapter 48 and the drill
check behaviour.

    python3 ch50/capstone/verify_capstone.py [NAMESPACE]   default: shop

Set KUBECTL=oc on OpenShift.
"""
import json
import os
import shutil
import subprocess
import sys

KUBECTL = os.environ.get("KUBECTL", "kubectl")
NS = sys.argv[1] if len(sys.argv) > 1 else "shop"
results = []


def get(kind, namespace=NS):
    cmd = [KUBECTL, "get", kind, "-o", "json"]
    cmd += ["-n", namespace] if namespace else []
    out = subprocess.run(cmd, capture_output=True, text=True)
    return json.loads(out.stdout)["items"] if out.returncode == 0 else []


def check(req, text, ok):
    results.append(ok)
    print(f"{'PASS' if ok else 'FAIL'}  {req:<3} {text}")


def main():
    ns = next((n for n in get("namespaces", None)
               if n["metadata"]["name"] == NS), None)
    labels = ns["metadata"].get("labels", {}) if ns else {}
    ambient = labels.get("istio.io/dataplane-mode") == "ambient"   # (1)
    print(f"namespace {NS}: {'ambient' if ambient else 'sidecar'} mode\n")

    pas = get("peerauthentications.security.istio.io")
    check("R2", "PeerAuthentication STRICT for the namespace",
          any(not p["spec"].get("selector") and
              p["spec"].get("mtls", {}).get("mode") == "STRICT"
              for p in pas))

    aps = get("authorizationpolicies.security.istio.io")
    check("R5", "an allow-nothing policy",
          any(not a.get("spec") for a in aps))
    allows = [a for a in aps if a.get("spec", {}).get("rules")
              and a["spec"].get("action", "ALLOW") == "ALLOW"]
    check("R5", "every ALLOW rule names its callers",
          all("from" in r for a in allows for r in a["spec"]["rules"]))

    def on_orders(spec):                                          # (2)
        if ambient:
            return any(t.get("kind") == "Service" and
                       t.get("name") == "orders"
                       for t in spec.get("targetRefs", []))
        return spec.get("selector", {}).get("matchLabels", {}).get(
            "app") == "orders"

    ras = get("requestauthentications.security.istio.io")
    check("R3", "RequestAuthentication for orders",
          any(on_orders(r["spec"]) for r in ras))
    check("R3", "the gateway's requests to orders need a JWT",
          any(on_orders(a["spec"]) and any(
              "*" in s.get("source", {}).get("requestPrincipals", [])
              for r in a["spec"]["rules"] for s in r.get("from", []))
              for a in allows))

    tels = get("telemetries.telemetry.istio.io")
    rates = [t.get("randomSamplingPercentage") for x in tels
             if not x["spec"].get("selector")
             for t in x["spec"].get("tracing", [])]
    check("R4", "tracing between 1% and 100% for the namespace",
          any(r is not None and 1 <= r <= 100 for r in rates))

    ros = get("rollouts.argoproj.io")
    inv = next((r for r in ros if r["metadata"]["name"] == "inventory"), None)
    canary = inv["spec"]["strategy"].get("canary", {}) if inv else {}
    check("R1", "Rollout inventory with mesh traffic routing",
          bool(canary.get("trafficRouting")))
    check("R1", "background analysis in the Rollout",
          bool(canary.get("analysis", {}).get("templates")))
    ats = get("analysistemplates.argoproj.io")
    metrics = [m for a in ats for m in a["spec"].get("metrics", [])]
    check("R1", "analysis query survives a canary without errors",
          any("or vector(0)" in m.get("provider", {}).get("prometheus", {})
              .get("query", "") for m in metrics))               # (3)
    check("R1", "one failed measurement does not abort the release",
          any(m.get("failureLimit", 0) >= 1 for m in metrics))

    if ambient:                                                   # (4)
        gws = get("gateways.gateway.networking.k8s.io")
        waypoints = [g["metadata"]["name"] for g in gws
                     if g["spec"].get("gatewayClassName") == "istio-waypoint"]
        check("R6", "a waypoint for the namespace", bool(waypoints))
        check("R6", "the namespace uses that waypoint",
              labels.get("istio.io/use-waypoint") in waypoints)
        check("R5", "an allow-nothing policy on the waypoint",
              any(not a["spec"].get("rules") and any(
                  t.get("kind") == "Gateway" and t.get("name") in waypoints
                  for t in a["spec"].get("targetRefs", []))
                  for a in aps))
        svc = next((s for s in get("services")
                    if s["metadata"]["name"] == "orders"), None)
        check("R6", "the gateway sends orders' traffic through the waypoint",
              (svc or {}).get("metadata", {}).get("labels", {}).get(
                  "istio.io/ingress-use-waypoint") == "true")

    if shutil.which("istioctl"):
        out = subprocess.run(["istioctl", "analyze", "-n", NS,
                              "--failure-threshold", "Warning"],
                             capture_output=True, text=True)
        check("R5", "istioctl analyze finds no warnings or errors",
              out.returncode == 0)

    print(f"\n{sum(results)} of {len(results)} checks passed")
    return 0 if all(results) else 1


if __name__ == "__main__":
    sys.exit(main())
