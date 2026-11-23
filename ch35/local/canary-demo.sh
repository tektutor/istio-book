#!/usr/bin/env bash
# Sends 100 requests through the canary route of Lab 35.3 with the lab's
# timeout and retries, and 100 through the same route without the
# retries, then reads the three access logs: the client's, v1's and v2's.
# You need Envoy as envoy, and python3.
#
# Usage: ch35/local/canary-demo.sh       (from the repository root)
set -uo pipefail

rm -f /tmp/ch35-canary-*.log
LOGS=$(mktemp -d)
PIDS=()
start() { "$@" > "$LOGS/$RANDOM.log" 2>&1 & PIDS+=($!); }
trap 'kill "${PIDS[@]}" 2>/dev/null; wait 2>/dev/null; rm -rf "$LOGS"' EXIT
HOST=127.0.0.1 PORT=18981 VERSION=v1 start python3 ch35/local/canary_api.py
HOST=127.0.0.1 PORT=18982 VERSION=v2 DELAY_SECONDS=2 \
  start python3 ch35/local/canary_api.py                           # (1)
touch /tmp/ch35-canary-{client,v1,v2}.log
start envoy -c ch35/local/canary-envoy.yaml --base-id 79 --log-level error \
  --file-flush-interval-msec 100
until curl -s http://127.0.0.1:19970/ready | grep -q LIVE; do sleep 0.5; done

send() {                                     # send PORT: 100 calls, one by one
  for i in $(seq 1 100); do
    curl -s -o /dev/null -w "%{http_code}\n" "http://127.0.0.1:$1/api/items/$i"
  done | sort | uniq -c
}
summary() {                                  # code, flags, details, cluster
  awk '{print $5, $6, $7, $19}' "$1" | sort | uniq -c | sort -rn
}
durations() {                                # the slowest and fastest failure
  awk '$5 != 200 {print $12}' "$1" | sort -n | sed -n '1p;$p' | paste -sd' '
}
for port in 18970 18975; do
  for f in /tmp/ch35-canary-*.log; do : > "$f"; done            # (2)
  if [ "$port" = 18970 ]; then
    echo "### With timeout 1s, 2 retries, perTryTimeout 400ms"
  else
    echo "### With timeout 1s and Istio's default retry policy"
  fi
  echo "# what the caller got"
  send "$port"
  sleep 3                                    # the slow answers finish
  echo "# client sidecar: code, flags, details, cluster"
  summary /tmp/ch35-canary-client.log
  echo "# client sidecar: fastest and slowest failed request, in ms"
  durations /tmp/ch35-canary-client.log
  echo "# requests that reached each version"                        # (3)
  for v in v1 v2; do
    printf '%s %s  ' $v "$(wc -l < /tmp/ch35-canary-$v.log)"
  done
  echo
  echo "# v2 sidecar: code, flags, details"
  awk '{print $5, $6, $7}' /tmp/ch35-canary-v2.log | sort | uniq -c
  id=$(awk '$5 != 200 {gsub(/"/, "", $16); print $16; exit}' \
    /tmp/ch35-canary-client.log)
  echo "# one failed request, followed by its x-request-id $id"       # (4)
  for f in client v1 v2; do
    grep -F "$id" "/tmp/ch35-canary-$f.log" |
      awk -v f="$f" '{print f, $1, $5, $6, $7, $12 "ms"}'
  done
done
