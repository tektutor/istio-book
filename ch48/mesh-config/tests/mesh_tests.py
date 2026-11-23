#!/usr/bin/env python3
"""Runs the mesh regression tests in a cases file against a cluster.

Each case sends one request from a test client pod and checks the HTTP
status code, and optionally a pattern in the response body. The client
pods run with the service accounts of real callers, so each request
carries the identity that the policies check.

    python3 tests/mesh_tests.py tests/cases.txt

A new policy reaches the proxies within seconds, but connections that
were open before the change keep the old policy until the proxy's drain
time ends: 45 seconds by default. So the script waits SETTLE_SECONDS
first, and tries a failed case again until RETRY_SECONDS have passed.
Set KUBECTL=oc on OpenShift.
The exit code is the number of failures.
"""
import os
import re
import subprocess
import sys
import time

KUBECTL = os.environ.get("KUBECTL", "kubectl")
SETTLE_SECONDS = float(os.environ.get("SETTLE_SECONDS", "50"))
RETRY_SECONDS = float(os.environ.get("RETRY_SECONDS", "10"))


def call(caller, method, url, header):
    """Send one request from the pod NAMESPACE/POD; return code, body."""
    namespace, pod = caller.split("/")
    command = [KUBECTL, "exec", "-n", namespace, pod, "-c", "client",
               "--", "curl", "-s", "-m", "5", "-X", method,
               "-w", "\n%{http_code}", url]                    # (1)
    if header:
        command[-1:-1] = ["-H", header]
    result = subprocess.run(command, capture_output=True, text=True)
    body, _, code = result.stdout.rpartition("\n")
    return code or "000", body


def check(expect, code, body):
    """expect is a status code such as 200, or 200~PATTERN to also
    search the body for a regular expression."""
    want_code, _, pattern = expect.partition("~")             # (2)
    if code != want_code:
        return False
    return not pattern or re.search(pattern, body) is not None


def main(path):
    failures = 0
    time.sleep(SETTLE_SECONDS)
    with open(path) as cases:
        for number, line in enumerate(cases, 1):
            fields = line.split("#")[0].split()
            if not fields:
                continue
            caller, method, url, expect = fields[:4]
            header = fields[4] if len(fields) > 4 else ""
            deadline = time.monotonic() + RETRY_SECONDS
            while True:                                       # (3)
                code, body = call(caller, method, url, header)
                ok = check(expect, code, body)
                if ok or time.monotonic() > deadline:
                    break
                time.sleep(2)
            failures += not ok
            print(f"{'pass' if ok else 'FAIL'}  line {number:<3} "
                  f"{caller:<18} {method:<4} {url}  "
                  f"want {expect}, got {code}")              # (4)
    print(f"{failures} failed")
    return failures


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
