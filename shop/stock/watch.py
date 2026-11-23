"""Opens one WatchStock stream and prints each update with the time
since the start, until the stream ends or the time limit is reached.

Usage: python watch.py <host:port> [seconds]            (default 12)
"""
import sys
import time

import grpc

import stock_pb2
import stock_pb2_grpc

target = sys.argv[1]
limit = float(sys.argv[2]) if len(sys.argv) > 2 else 12
start = time.monotonic()
with grpc.insecure_channel(target) as channel:
    stub = stock_pb2_grpc.StockServiceStub(channel)
    stream = stub.WatchStock(stock_pb2.GetStockRequest(sku="SKU-2"),
                             timeout=limit)
    try:
        for level in stream:
            print(f"{time.monotonic() - start:5.1f}s  {level.sku}="
                  f"{level.quantity} from {level.pod}")
    except grpc.RpcError as err:                                 # (1)
        print(f"{time.monotonic() - start:5.1f}s  stream ended: "
              f"{err.code().name} {err.details()}")
