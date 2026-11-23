"""The TekTutor Shop stock service, a gRPC server on port 9090.

    tektutor.stock.v1.StockService/GetStock    one stock level
    tektutor.stock.v1.StockService/WatchStock  a stream of stock levels
    grpc.health.v1.Health/Check                the standard health check

Every answer names the pod that sent it, so you can see how the calls
are spread over the replicas.
"""
import logging
import os
import random
import time
from concurrent import futures

import grpc
from grpc_health.v1 import health, health_pb2, health_pb2_grpc
from grpc_reflection.v1alpha import reflection

import stock_pb2
import stock_pb2_grpc

POD = os.environ.get("POD_NAME", "local")
PORT = int(os.environ.get("PORT", "9090"))
STOCK = {"SKU-1": 42, "SKU-2": 7, "SKU-3": 0}
log = logging.getLogger("stock")


class StockService(stock_pb2_grpc.StockServiceServicer):
    def GetStock(self, request, context):
        if request.sku not in STOCK:
            context.abort(grpc.StatusCode.NOT_FOUND,             # (1)
                          f"unknown sku {request.sku}")
        return stock_pb2.StockLevel(sku=request.sku,
                                    quantity=STOCK[request.sku], pod=POD)

    def WatchStock(self, request, context):
        if request.sku not in STOCK:
            context.abort(grpc.StatusCode.NOT_FOUND,
                          f"unknown sku {request.sku}")
        interval = float(os.environ.get("WATCH_INTERVAL", "5"))
        while context.is_active():                               # (2)
            level = max(0, STOCK[request.sku] + random.randint(-2, 2))
            yield stock_pb2.StockLevel(sku=request.sku, quantity=level,
                                       pod=POD)
            time.sleep(interval)


def serve():
    server = grpc.server(futures.ThreadPoolExecutor(max_workers=16))
    stock_pb2_grpc.add_StockServiceServicer_to_server(StockService(),
                                                      server)
    checker = health.HealthServicer()
    health_pb2_grpc.add_HealthServicer_to_server(checker, server)
    checker.set("", health_pb2.HealthCheckResponse.SERVING)      # (3)
    names = (stock_pb2.DESCRIPTOR.services_by_name["StockService"]
             .full_name, health.SERVICE_NAME, reflection.SERVICE_NAME)
    reflection.enable_server_reflection(names, server)           # (4)
    server.add_insecure_port(f"[::]:{PORT}")                     # (5)
    server.start()
    log.info("pod=%s listening on %d", POD, PORT)
    server.wait_for_termination()


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    serve()
