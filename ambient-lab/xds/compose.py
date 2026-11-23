"""Builds a ztunnel configuration from base.yaml and change files.

Each change file can add workloads, Services and policies, change
fields of Services and workloads by name, and remove policies:

    addWorkloads: [...]          addServices: [...]
    addPolicies: [...]           removePolicies: [name, ...]
    setServices: {name: {field: value}}
    setWorkloads: {name: {field: value}}

Usage: python3 compose.py base.yaml change.yaml ... > config.yaml
"""
import sys

import yaml


class Tagged:
    """A value with a YAML tag, such as !Exact, which ztunnel's format uses
    for string matches. PyYAML keeps it as it is."""

    def __init__(self, tag, value):
        self.tag, self.value = tag, value


def load_tagged(loader, tag, node):
    if isinstance(node, yaml.SequenceNode):              # such as !Presence []
        return Tagged("!" + tag, loader.construct_sequence(node))
    return Tagged("!" + tag, loader.construct_scalar(node))


def dump_tagged(dumper, t):
    if isinstance(t.value, list):
        return dumper.represent_sequence(t.tag, t.value, flow_style=True)
    return dumper.represent_scalar(t.tag, t.value)


yaml.SafeLoader.add_multi_constructor("!", load_tagged)
yaml.SafeDumper.add_representer(Tagged, dump_tagged)

config = yaml.safe_load(open(sys.argv[1]))
config.setdefault("policies", [])
for path in sys.argv[2:]:
    change = yaml.safe_load(open(path)) or {}
    drop = set(change.get("removePolicies", []))
    config["policies"] = [p for p in config["policies"] if p["name"] not in drop]
    config["workloads"] += change.get("addWorkloads", [])
    config["services"] += change.get("addServices", [])
    config["policies"] += change.get("addPolicies", [])
    for kind, key in (("services", "setServices"),
                      ("workloads", "setWorkloads")):
        for name, fields in change.get(key, {}).items():
            matches = [o for o in config[kind] if o["name"] == name]
            if not matches:
                sys.exit(f"{path}: no {kind[:-1]} named {name}")
            for obj in matches:
                obj.update(fields)
yaml.safe_dump(config, sys.stdout, sort_keys=False)
