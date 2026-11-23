"""Sends 20 requests per second through Envoy and prints, for every
second, how many answers came from each zone and how many failed. At
second FAIL_AT, it writes FAILURES into the file "down" of backends.py.

Usage: run.py SECONDS FAIL_AT "zone-a 503[;zone-b 503 ...]" """
import collections
import os
import sys
import time
import urllib.request

seconds, fail_at, failures = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3]
DOWN = os.path.join(os.path.dirname(os.path.abspath(__file__)), "down")
COLUMNS = ["zone-a", "zone-b", "zone-c", "dr-a", "errors"]

print("second " + " ".join(f"{c:>7}" for c in COLUMNS))
start = time.time()
for second in range(seconds):
    if second == fail_at:
        with open(DOWN, "w") as f:
            f.write(failures.replace(";", "\n") + "\n")
    count = collections.Counter()
    for i in range(20):
        time.sleep(max(0, start + second + i * 0.05 - time.time()))
        try:
            with urllib.request.urlopen("http://127.0.0.1:18700/",
                                        timeout=5) as answer:
                count[answer.read().decode().strip()] += 1
        except Exception:                                            # (1)
            count["errors"] += 1
    note = "  <- " + failures if second == fail_at else ""
    print(f"{second:>6} " + " ".join(f"{count[c]:>7}" for c in COLUMNS)
          + note, flush=True)
