"""Tests for the orders service. Run them with: pytest"""
import httpx
from fastapi.testclient import TestClient

import app


def fake_inventory(statuses):
    """An inventory stand-in that answers with the given status codes."""
    calls = []

    def handler(request):
        calls.append(request)
        status = statuses[min(len(calls), len(statuses)) - 1]
        body = {"sku": "SKU-7", "available": 42, "pod": "inv"}
        return httpx.Response(status, json=body if status == 200 else None)
    return httpx.MockTransport(handler), calls


def test_order_includes_the_stock_level():
    transport, calls = fake_inventory([200])
    app.client = httpx.AsyncClient(transport=transport)
    resp = TestClient(app.app).get("/api/orders/7",
                                   headers={"x-request-id": "abc"})
    assert resp.status_code == 200
    assert resp.json()["stock"]["available"] == 42
    assert calls[0].headers["x-request-id"] == "abc"   # header copied


def test_app_retries_try_again_after_a_failure():
    transport, calls = fake_inventory([503, 200])
    app.client = httpx.AsyncClient(transport=transport)
    app.APP_RETRIES = 2
    resp = TestClient(app.app).get("/api/orders/7")
    app.APP_RETRIES = 0
    assert resp.json()["appTries"] == 2 and len(calls) == 2


def test_failure_after_the_last_try_is_a_502():
    transport, calls = fake_inventory([503])
    app.client = httpx.AsyncClient(transport=transport)
    resp = TestClient(app.app).get("/api/orders/7")
    assert resp.status_code == 502 and len(calls) == 1
