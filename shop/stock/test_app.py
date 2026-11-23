"""Tests for the stock service. Run with: python -m pytest"""
import threading

import grpc
import pytest

import app
import stock_pb2
import stock_pb2_grpc


@pytest.fixture(scope="module")
def stub():
    app.PORT = 19190
    threading.Thread(target=app.serve, daemon=True).start()
    channel = grpc.insecure_channel("127.0.0.1:19190")
    grpc.channel_ready_future(channel).result(timeout=5)
    yield stock_pb2_grpc.StockServiceStub(channel)
    channel.close()


def test_get_stock(stub):
    reply = stub.GetStock(stock_pb2.GetStockRequest(sku="SKU-1"))
    assert reply.quantity == 42
    assert reply.pod == "local"


def test_unknown_sku(stub):
    with pytest.raises(grpc.RpcError) as err:
        stub.GetStock(stock_pb2.GetStockRequest(sku="SKU-9"))
    assert err.value.code() == grpc.StatusCode.NOT_FOUND


def test_watch_stock(stub):
    app.os.environ["WATCH_INTERVAL"] = "0.01"
    stream = stub.WatchStock(stock_pb2.GetStockRequest(sku="SKU-2"))
    levels = [next(stream).quantity for _ in range(3)]
    stream.cancel()
    assert all(5 <= q <= 9 for q in levels)
