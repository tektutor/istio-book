"""Moves the tenants of one cell to the other cells, a quarter at a time.
Step 1 moves the first quarter of the cell's tenants, step 4 all of them.
Each moved tenant goes to the other cell with the fewest tenants.

Usage: python3 ch42/router/drain.py CELL STEP < tenants.txt > new.txt"""
import collections
import math
import sys

cell, step = sys.argv[1], int(sys.argv[2])
rows = [line.split() for line in sys.stdin
        if line.strip() and not line.startswith("#")]
home = dict(rows)
own = sorted(t for t, c in home.items() if c == cell)               # (1)
moving = own[:math.ceil(len(own) * step / 4)]
for tenant in moving:
    load = collections.Counter(c for c in home.values() if c != cell)
    target = min(sorted(load), key=lambda c: load[c])               # (2)
    home[tenant] = target
print("# tenant     home cell")
for tenant, c in rows:
    print(f"{tenant:<12} {home[tenant]}")
