#!/usr/bin/env bash
# Starts three stock servers and one Envoy, then sends 30 gRPC calls
# over one channel through each listener and counts the answering pods.
# Last, it opens a stream with a 3-second gap between updates, with and
# without a stream idle timeout.
# You need Envoy on your PATH and a Python environment with the
# packages in shop/stock/requirements.txt.
#
# Usage: ch22/local/grpc-lb-demo.sh       (from the repository root)
set -uo pipefail

W=/tmp/ch22-stock                                              # (1)
rm -rf $W && mkdir -p $W
cp shop/stock/stock.proto shop/stock/*.py $W/
(cd $W && python3 -m grpc_tools.protoc -I. --python_out=. \
   --grpc_python_out=. stock.proto)

PIDS=()
cleanup() { kill "${PIDS[@]}" 2>/dev/null; }
trap cleanup EXIT
for n in 1 2 3; do
  (cd $W && POD_NAME=stock-$n PORT=1909$n WATCH_INTERVAL=3 \
     exec python3 app.py) 2>/dev/null & PIDS+=($!)
done
envoy -c ch22/local/grpc-lb-envoy.yaml --base-id 47 --log-level error \
  > /tmp/envoy-grpc.log 2>&1 & PIDS+=($!)
sleep 3

echo "### Layer 4: one server per connection"
(cd $W && python3 client.py 127.0.0.1:18900 30)
echo "### Layer 7: one server per request"
(cd $W && python3 client.py 127.0.0.1:18901 30)
echo "### A stream with an update every 3 seconds, no idle timeout"
(cd $W && python3 watch.py 127.0.0.1:18901 10)
echo "### The same stream behind a 2-second stream idle timeout"
(cd $W && python3 watch.py 127.0.0.1:18902 10)                 # (2)
