#!/usr/bin/env python3
"""Compare two sets of Kubernetes manifests, such as the output of
istioctl manifest generate and helm template.

Usage: compare_installs.py A.yaml[,A2.yaml...] B.yaml[,B2.yaml...]

It prints the objects that only one side has, and the objects that
both sides have but with different content. Labels and annotations are
ignored, because each tool adds its own.
"""
import json
import sys

import yaml


def load(paths):
    """Read every document in the files; key each object by kind/name."""
    objects = {}
    for path in paths.split(","):
        with open(path) as f:
            for doc in yaml.safe_load_all(f):
                if doc:                                        # (1)
                    key = f"{doc['kind']}/{doc['metadata']['name']}"
                    objects[key] = doc
    return objects


def without_labels(obj):
    """A copy of the object without its labels and annotations."""
    copy = json.loads(json.dumps(obj))
    copy["metadata"].pop("labels", None)
    copy["metadata"].pop("annotations", None)
    return copy


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    a, b = load(sys.argv[1]), load(sys.argv[2])
    print(f"A has {len(a)} objects, B has {len(b)} objects")
    for key in sorted(a.keys() - b.keys()):
        print(f"  only in A: {key}")
    for key in sorted(b.keys() - a.keys()):
        print(f"  only in B: {key}")
    for key in sorted(a.keys() & b.keys()):                    # (2)
        if without_labels(a[key]) != without_labels(b[key]):
            print(f"  different: {key}")


if __name__ == "__main__":
    main()
