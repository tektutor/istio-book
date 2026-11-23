#!/usr/bin/env bash
# Starts a throwaway PostgreSQL on port 15432 and an Envoy TCP proxy with
# a three-second idle timeout on port 15433, then runs
# ch27/python/db_pool.py through the proxy.
# You need PostgreSQL 16 or later (initdb and pg_ctl on your PATH), Envoy,
# and python3 with sqlalchemy and psycopg[binary]. Do not run it as root:
# PostgreSQL refuses to start as root.
#
# Usage: ch27/local/db-demo.sh       (from the repository root)
set -euo pipefail

DIR=$(mktemp -d /tmp/ch27-pg.XXXXXX)
ENVOY=
cleanup() {
  pg_ctl -D "$DIR/data" -m immediate stop > /dev/null 2>&1 || true
  [ -n "$ENVOY" ] && kill "$ENVOY" 2>/dev/null
  rm -rf "$DIR"
}
trap cleanup EXIT

echo lab-only-password > "$DIR/password"
initdb -D "$DIR/data" -U shop --pwfile="$DIR/password" \
  --auth=scram-sha-256 --encoding=UTF8 --locale=C > /dev/null  # (1)
pg_ctl -D "$DIR/data" -l "$DIR/postgres.log" -w start \
  -o "-p 15432 -k $DIR -c listen_addresses=127.0.0.1" > /dev/null
PGPASSWORD=lab-only-password createdb -h 127.0.0.1 -p 15432 -U shop shop

envoy -c ch27/local/db-envoy.yaml --base-id 56 --log-level error \
  > "$DIR/envoy.log" 2>&1 &
ENVOY=$!
until curl -s http://127.0.0.1:19928/ready 2>/dev/null | grep -q LIVE
do kill -0 "$ENVOY" || exit 1; sleep 0.2; done

python3 ch27/python/db_pool.py                                 # (2)
