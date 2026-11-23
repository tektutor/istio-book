"""Calls GetStock many times over one gRPC channel and counts which pod
answered each call.

Usage: python client.py <host:port> [calls]          (default 30 calls)
"""
import collections
import sys

import grpc

import stock_pb2
import stock_pb2_grpc

target = sys.argv[1]
calls = int(sys.argv[2]) if len(sys.argv) > 2 else 30
pods = collections.Counter()
with grpc.insecure_channel(target) as channel:                   # (1)
    stub = stock_pb2_grpc.StockServiceStub(channel)
    for _ in range(calls):
        reply = stub.GetStock(stock_pb2.GetStockRequest(sku="SKU-1"),
                              timeout=5)
        pods[reply.pod] += 1
for pod, count in sorted(pods.items()):
    print(f"{pod}: {count}")
