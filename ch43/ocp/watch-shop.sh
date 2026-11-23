#!/usr/bin/env bash
# Calls the shop through its Route five times a second and prints, every
# ten seconds, how many answers had each status code. Stop with Ctrl+C.
#
# Usage: ch43/ocp/watch-shop.sh
HOST=$(oc get route shop -n shop -o jsonpath='{.spec.host}')
while true; do
  for i in $(seq 50); do
    curl -sk -o /dev/null -m 5 -w '%{http_code}\n' "https://$HOST/"
    sleep 0.2
  done | sort | uniq -c | tr '\n' ' '                          # (1)
  echo " $(date +%T)"
done
