#!/usr/bin/env bash
# Sends one request with the trace headers that a sidecar adds to
# ch27/python/tracing_demo.py, first without OpenTelemetry and then with
# it, and prints the headers that reached the service's outgoing call.
# You need python3 with the packages in ch27/python/requirements.txt.
#
# Usage: ch27/local/tracing-demo.sh       (from the repository root)
set -uo pipefail

TP=00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01     # (1)
RID=6f1c2a9e-3b7d-4c55-9e0a-2d4b8f7a1c33
for mode in off otel; do
  TRACING=$mode python3 ch27/python/tracing_demo.py 18500 &
  APP=$!
  until curl -s -o /dev/null http://127.0.0.1:18500/echo
  do kill -0 $APP || exit 1; sleep 0.2; done
  echo "### TRACING=$mode"
  curl -s -H "traceparent: $TP" -H "x-request-id: $RID" \
    http://127.0.0.1:18500/api/check | python3 -m json.tool       # (2)
  kill $APP; wait $APP 2>/dev/null
done
