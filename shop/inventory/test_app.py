"""Tests for the inventory service. Run them with: pytest"""
from fastapi.testclient import TestClient

import app

client = TestClient(app.app)


def setup_function():
    client.post("/admin/faults")               # back to the defaults


def test_stock_answers_with_the_pod_name():
    resp = client.get("/api/stock/SKU-7")
    assert resp.status_code == 200
    assert resp.json() == {"sku": "SKU-7", "available": 42, "pod": "local"}


def test_fail_100_returns_the_configured_code():
    client.post("/admin/faults?fail=100&code=500")
    assert client.get("/api/stock/SKU-7").status_code == 500


def test_missing_parameters_reset_to_defaults():
    client.post("/admin/faults?fail=50&delay=2s")
    resp = client.post("/admin/faults")
    assert resp.json() == {"fail": 0, "code": 503, "delay": "0s"}


def test_bad_parameters_are_rejected():
    for query in ["fail=101", "code=200", "delay=fast", "fail=x"]:
        assert client.post("/admin/faults?" + query).status_code == 400


def test_duration_parsing_and_formatting():
    assert app.parse_duration("200ms") == 0.2
    assert app.parse_duration("3s") == 3.0
    assert [app.seconds(v) for v in (0, 0.25, 2, 1.9964)] == \
        ["0s", "250ms", "2s", "1.996s"]
