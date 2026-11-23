"""A small stand-in for Envoy's reference rate limit service. It keeps
its counters in memory instead of Redis, and knows one domain:

    shop
      path=orders-api                50 requests per second, shared
        client=<any value>           10 requests per second per value

Usage: python3 rls.py [port]                       (default 18181)
Generate rls_pb2.py and rls_pb2_grpc.py first:
    python3 -m grpc_tools.protoc -I. --python_out=. \
      --grpc_python_out=. rls.proto
"""
import collections
import sys
import threading
import time
from concurrent import futures

import grpc

import rls_pb2
import rls_pb2_grpc

LIMITS = {                                                       # (1)
    ("shop", ("path", "orders-api")): 50,
    ("shop", ("path", "orders-api"), ("client", "*")): 10,
}
counters = collections.Counter()
lock = threading.Lock()


def limit_for(domain, entries):
    """The limit of the most specific rule; '*' matches any value."""
    exact = (domain, *entries)
    if exact in LIMITS:
        return LIMITS[exact]
    wild = (domain, *entries[:-1], (entries[-1][0], "*"))
    return LIMITS.get(wild)


class RateLimit(rls_pb2_grpc.RateLimitServiceServicer):
    def ShouldRateLimit(self, request, context):
        window = int(time.time())                                # (2)
        code = rls_pb2.RateLimitResponse.OK
        for d in request.descriptors:
            entries = tuple((e.key, e.value) for e in d.entries)
            limit = limit_for(request.domain, entries)
            if limit is None:
                continue
            key = (window, request.domain, entries)
            with lock:
                counters[key] += request.hits_addend or 1
                used = counters[key]
            if used > limit:
                code = rls_pb2.RateLimitResponse.OVER_LIMIT     # (3)
        return rls_pb2.RateLimitResponse(overall_code=code)


port = int(sys.argv[1]) if len(sys.argv) > 1 else 18181
server = grpc.server(futures.ThreadPoolExecutor(max_workers=8))
rls_pb2_grpc.add_RateLimitServiceServicer_to_server(RateLimit(), server)
server.add_insecure_port(f"127.0.0.1:{port}")
server.start()
server.wait_for_termination()
