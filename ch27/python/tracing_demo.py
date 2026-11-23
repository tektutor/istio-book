"""A small service that shows trace header propagation in Python.

    GET /api/check  calls GET /echo on this service with httpx, and
                    returns the headers that /echo received
    GET /echo       returns the tracing headers of the request

With TRACING=otel, OpenTelemetry copies the trace headers to the call.
With TRACING=off, the call carries no trace headers, as in a service
that never copies them.

Usage: TRACING=otel python3 tracing_demo.py [port]   (default 18500)
"""
import contextvars
import os
import sys

import httpx
import uvicorn
from fastapi import FastAPI, Request

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 18500
TRACING = os.environ.get("TRACING", "otel")
SHOWN = ["traceparent", "x-b3-traceid", "x-b3-spanid", "x-b3-sampled",
         "x-request-id"]

app = FastAPI()
client = httpx.AsyncClient(base_url=f"http://127.0.0.1:{PORT}")

if TRACING == "otel":
    from opentelemetry import trace
    from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
    from opentelemetry.instrumentation.httpx import HTTPXClientInstrumentor
    from opentelemetry.propagate import set_global_textmap
    from opentelemetry.propagators.b3 import B3MultiFormat
    from opentelemetry.propagators.composite import CompositePropagator
    from opentelemetry.sdk.trace import TracerProvider
    from opentelemetry.trace.propagation.tracecontext import (
        TraceContextTextMapPropagator)

    trace.set_tracer_provider(TracerProvider())                 # (1)
    set_global_textmap(CompositePropagator(                     # (2)
        [TraceContextTextMapPropagator(), B3MultiFormat()]))
    FastAPIInstrumentor.instrument_app(app)                     # (3)
    HTTPXClientInstrumentor.instrument_client(client)

# x-request-id is not a trace header, so OpenTelemetry does not copy it.
# The proxies use it to match access log lines, so copy it yourself.
request_id = contextvars.ContextVar("request_id", default=None)


async def copy_request_id(request: httpx.Request):              # (4)
    if request_id.get():
        request.headers["x-request-id"] = request_id.get()

client.event_hooks["request"].append(copy_request_id)


@app.get("/api/check")
async def check(request: Request):
    request_id.set(request.headers.get("x-request-id"))
    resp = await client.get("/echo")
    return resp.json()


@app.get("/echo")
async def echo(request: Request):
    return {h: request.headers[h] for h in SHOWN if h in request.headers}


if __name__ == "__main__":
    uvicorn.run(app, host="127.0.0.1", port=PORT, log_level="warning")
