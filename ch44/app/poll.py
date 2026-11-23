# Calls URL every INTERVAL seconds for DURATION seconds. Prints a line only
# when the result changes, with the time since the start, and the count of
# each status code at the end.
#
# Usage: python3 poll.py URL DURATION INTERVAL
import collections, sys, time, urllib.error, urllib.request

url = sys.argv[1]
duration, interval = float(sys.argv[2]), float(sys.argv[3])
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
start, last, counts = time.time(), None, collections.Counter()


def stamp(t):
    return "+%02d:%04.1f" % (int(t // 60), t % 60)


while time.time() - start < duration:
    t = time.time() - start
    try:
        with opener.open(url, timeout=3) as r:                      # (1)
            result = "%d %s" % (r.status, r.read(200).decode().strip())
    except urllib.error.HTTPError as e:
        result = "%d %s" % (e.code, e.read(300).decode().strip())
    except Exception as e:
        result = "ERR %s" % e
    counts[result.split()[0]] += 1
    if result != last:                                              # (2)
        print(stamp(t), result, flush=True)
        last = result
    time.sleep(interval)
print("totals:", dict(counts), flush=True)
