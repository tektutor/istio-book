#!/usr/bin/env bash
# Runs Envoy with one of the envoy-*.yaml files, sends 20 requests per
# second through it, fails one or more zones, and prints where the
# answers came from, followed by Envoy's ejection and zone counters.
#
# Usage: ch41/local/failover-demo.sh SCENARIO
#   no-outlier | outlier | refuse | region | same-zone |
#   zone-aware | zone-aware-min1 | zone-aware-5
set -euo pipefail
cd "$(dirname "$0")"
ENVOY=${ENVOY:-envoy}

case ${1:?scenario} in                                              # (1)
  no-outlier)      cfg=envoy-no-outlier.yaml;     run="6 3 zone-a 503" ;;
  outlier)         cfg=envoy-outlier.yaml;        run="9 3 zone-a 503" ;;
  refuse)          cfg=envoy-outlier.yaml;        run="7 3 zone-a refuse" ;;
  region)          cfg=envoy-outlier.yaml
                   run="7 3 zone-a 503;zone-b 503;zone-c 503" ;;
  same-zone)       cfg=envoy-same-zone.yaml;      run="7 3 zone-a 503" ;;
  zone-aware)      cfg=envoy-zone-aware.yaml;     run="3 99 -" ;;
  zone-aware-min1) cfg=envoy-zone-aware-min1.yaml; run="6 3 zone-a 503" ;;
  zone-aware-5)    cfg=envoy-zone-aware-5.yaml;   run="5 99 -" ;;
  *) echo "unknown scenario $1" >&2; exit 1 ;;
esac
read -r secs fail_at failures <<< "$run"

rm -f down
python3 backends.py & backends=$!
"$ENVOY" -c "$cfg" --base-id 41 --log-level error & envoy=$!
trap 'kill $backends $envoy 2>/dev/null; rm -f down' EXIT
until curl -s -o /dev/null http://127.0.0.1:18701/ready; do sleep 0.2; done

python3 run.py "$secs" "$fail_at" "$failures"
curl -s http://127.0.0.1:18701/stats |
  grep -E "^cluster\.ratings\.(outlier_detection\.ejections_enforced_total|\
lb_zone_cluster_too_small|lb_zone_routing_[a-z_]+|upstream_rq_retry):" # (2)
