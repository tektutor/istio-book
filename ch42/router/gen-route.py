"""Writes the HTTPRoute of the cell router from tenants.txt: one rule per
cell, which matches the x-tenant header of every tenant in that cell.
With --services, each cell is the gateway Service cell-gw-istio in the
namespace of the same name, as in the OpenShift lab.

Usage: python3 ch42/router/gen-route.py [--services] [tenants file]"""
import collections
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
args = sys.argv[1:]
services = "--services" in args
args = [a for a in args if a != "--services"]
path = args[0] if args else os.path.join(HERE, "tenants.txt")
cells = collections.defaultdict(list)
with open(path) as f:
    for line in f:
        if line.strip() and not line.startswith("#"):
            tenant, cell = line.split()
            if any(tenant in t for t in cells.values()):
                sys.exit(f"{tenant} is in the map twice")
            cells[cell].append(tenant)

print("""apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: cell-router
  namespace: router
spec:
  parentRefs:
  - name: cell-router
  rules:""")
if len(cells) > 16 or sum(len(t) for t in cells.values()) > 128:  # (1)
    sys.exit("more than 16 cells or 128 tenants; use a cell directory")
for cell in sorted(cells):
    if len(cells[cell]) > 64:
        sys.exit(f"{cell}: more than 64 tenants; use a cell directory")
    print("  - matches:")
    for tenant in sorted(cells[cell]):
        print(f"    - headers:\n      - name: x-tenant\n        value: {tenant}")
    if services:
        print(f"""    backendRefs:
    - name: cell-gw-istio
      namespace: {cell}
      port: 80""")
    else:
        print(f"""    backendRefs:
    - group: networking.istio.io
      kind: Hostname
      name: {cell}.cells.internal
      port: 80""")                                        # (2)
