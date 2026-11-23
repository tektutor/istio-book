"""Prints traces from Jaeger's query API as trees of spans.

Usage: curl -s 'http://127.0.0.1:16686/api/traces?service=orders.shop' |
         python3 show_traces.py [tag ...]
Each line shows the service, the operation, the span kind, the duration
and the tags named on the command line.
"""
import json
import sys

TAGS = sys.argv[1:]


def show(trace):
    services = {k: p["serviceName"] for k, p in trace["processes"].items()}
    spans = {s["spanID"]: s for s in trace["spans"]}
    children = {}
    for s in trace["spans"]:
        parent = next((r["spanID"] for r in s.get("references", [])
                       if r["refType"] == "CHILD_OF"
                       and r["spanID"] in spans), None)       # (1)
        children.setdefault(parent, []).append(s)
    count = f"{len(spans)} span" + ("s" if len(spans) != 1 else "")
    print(f"trace {trace['traceID']}: {count}")

    def walk(parent, depth):
        for s in sorted(children.get(parent, []), key=lambda s: s["startTime"]):
            tags = {t["key"]: t["value"] for t in s["tags"]}
            extra = " ".join(f"{k}={tags[k]}" for k in TAGS if k in tags)
            print(f"{'  ' * depth}- {services[s['processID']]} "
                  f"{s['operationName']} [{tags.get('span.kind', '?')}] "
                  f"{s['duration'] / 1000:.1f} ms {extra}".rstrip())
            walk(s["spanID"], depth + 1)
    walk(None, 1)


data = json.load(sys.stdin)["data"]
for trace in sorted(data, key=lambda t: min(s["startTime"] for s in t["spans"])):
    show(trace)
