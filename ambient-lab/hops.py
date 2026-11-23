"""Prints the connections that the ztunnels of the local lab logged.

For each hop it prints the node, the direction, the source and the
destination workloads, the Service, and the error if there is one. A
hop appears once: from the client's ztunnel, or for a hop that starts
at a waypoint, from the destination's ztunnel.
Only lines newer than MARK (a time from date +%s.%N) are printed.

Usage: python3 hops.py MARK [LAB folder]
"""
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

mark = float(sys.argv[1])
lab = Path(sys.argv[2] if len(sys.argv) > 2 else "/tmp/ambient-lab")
FIELD = re.compile(r'(\w+(?:\.\w+)?)=("(?:[^"\\]|\\.)*"|\S+)')

rows = []
for node in ("lab", "lab-m02"):
    log = lab / node / "ztunnel.log"
    for line in log.read_text().splitlines():
        if "\taccess\t" not in line:
            continue
        stamp = line.split("\t")[0].replace("Z", "+00:00")
        when = datetime.fromisoformat(stamp).replace(tzinfo=timezone.utc)
        when = when.timestamp()
        if when < mark:
            continue
        f = {k: v.strip('"').replace('\\"', '"')
             for k, v in FIELD.findall(line)}
        src = f.get("src.workload", "")
        if f.get("direction") != "outbound" and not src.startswith("waypoint") \
                and "error" not in f:
            continue                     # one line per hop, from its sender
        hop = f"{f.get('src.workload', f.get('src.addr', '?'))} -> " \
              f"{f.get('dst.workload', f.get('dst.addr', '?'))}"
        svc = f.get("dst.service", "-").split(".")[0]
        err = "\n" + " " * 9 + "error: " + f["error"] if "error" in f else ""
        rows.append((when, f"{node:8} {f.get('direction', '?'):9} "
                           f"{hop:32} service={svc}{err}"))
for _, row in sorted(rows):
    print(row)
