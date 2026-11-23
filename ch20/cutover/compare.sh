#!/usr/bin/env bash
# Sends the same requests to the old and the new ingress, and prints the
# status code, the redirect target and the X-Frame-Options header of
# each answer side by side. Lines that differ are marked DIFF.
# Each request gives up after 10 seconds, so an address that does not
# answer shows "- -" with no status code instead of stopping the script.
#
# Usage: ch20/cutover/compare.sh OLD_ADDRESS NEW_ADDRESS [requests file]
#   An address is an IP address, or IP:PORT for a non-standard port.
#   Set CA to the CA certificate file; default /tmp/lab-ca.crt.
set -uo pipefail
OLD=$1
NEW=$2
FILE=${3:-ch20/cutover/requests.txt}
CA=${CA:-/tmp/lab-ca.crt}

probe() {                                 # probe ADDRESS URL
  local addr=$1 url=$2 port=443
  [[ $url == http://* ]] && port=80
  [[ $addr == *:* ]] || addr="$addr:$port"
  curl -s -m 10 -o /dev/null -D - --noproxy "*" --cacert "$CA" \
    --connect-to "::$addr" "$url" |
    awk 'NR == 1 { code = $2 }
         tolower($1) == "location:" { loc = $2 }
         tolower($1) == "x-frame-options:" { xfo = $2 }
         END { gsub("\r", "", loc); gsub("\r", "", xfo)
               printf "%s %s %s", code, (loc ? loc : "-"),
                      (xfo ? xfo : "-") }'
}

printf "%-48s %-22s %-22s\n" "URL" "OLD" "NEW"
grep -v '^#' "$FILE" | while read -r url; do
  [ -z "$url" ] && continue
  a=$(probe "$OLD" "$url")
  b=$(probe "$NEW" "$url")
  mark=""
  [ "$a" != "$b" ] && mark="DIFF"
  printf "%-48s %-22s %-22s %s\n" "${url#*//}" "$a" "$b" "$mark"
done
