"""The TekTutor Shop orders service.

It answers order queries by calling the inventory service. It can also
retry failed calls in its own code, so you can see what happens when
the application and the mesh both retry the same request.

    GET /api/orders/{id}  returns an order with its stock level
    GET /healthz          liveness and readiness probe
"""
import asyncio
import logging
import os

import httpx
import uvicorn
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, PlainTextResponse

POD = os.environ.get("POD_NAME", "local")
INVENTORY_URL = os.environ.get("INVENTORY_URL", "http://inventory:8080")
APP_RETRIES = int(os.environ.get("APP_RETRIES", "0"))     # extra tries in code
CLIENT_TIMEOUT = float(os.environ.get("CLIENT_TIMEOUT", "15"))  # seconds
log = logging.getLogger("orders")

# Headers that carry tracing context. The mesh cannot copy them from
# the incoming request to the outgoing request, so the code must.
TRACE_HEADERS = ["traceparent", "tracestate", "x-request-id", "b3",
                 "x-b3-traceid", "x-b3-spanid", "x-b3-parentspanid",
                 "x-b3-sampled"]


class JSONLine(JSONResponse):
    """JSON with a newline at the end, so curl output ends cleanly."""

    def render(self, content) -> bytes:
        return super().render(content) + b"\n"


app = FastAPI(default_response_class=JSONLine)
client = httpx.AsyncClient(timeout=CLIENT_TIMEOUT)


async def unless_caller_leaves(request: Request, work):
    """Run work, but cancel it if the caller of this request goes away."""
    task = asyncio.ensure_future(work)
    while not task.done():
        if await request.is_disconnected():
            task.cancel()
            break
        await asyncio.wait({task}, timeout=0.05)
    return await task      # raises CancelledError if it was cancelled


@app.get("/api/orders/{order_id}")
async def order(order_id: str, request: Request):
    sku = f"SKU-{order_id}"
    url = f"{INVENTORY_URL}/api/stock/{sku}"
    # Copy the tracing headers, so the whole call chain is one trace.
    headers = {h: request.headers[h] for h in TRACE_HEADERS
               if h in request.headers}

    status, error, tries = 0, "", 0
    while tries < 1 + APP_RETRIES:                           # (1)
        tries += 1
        try:
            resp = await unless_caller_leaves(               # (2)
                request, client.get(url, headers=headers))
            status, error = resp.status_code, ""
            if status == 200:
                return {"id": order_id, "sku": sku, "stock": resp.json(),
                        "appTries": tries, "pod": POD}
        except asyncio.CancelledError:
            log.info("pod=%s order=%s caller went away", POD, order_id)
            return PlainTextResponse("caller went away\n", status_code=499)
        except httpx.HTTPError as exc:
            status, error = 0, type(exc).__name__
        log.info("pod=%s order=%s try=%d failed: status=%d error=%s",
                 POD, order_id, tries, status, error or "none")

    return PlainTextResponse(                                # (3)
        f"inventory failed after {tries} app tries "
        f"(status={status}, error={error or 'none'})\n", status_code=502)


@app.get("/healthz")
async def healthz():
    return PlainTextResponse("ok\n")


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, datefmt="%H:%M:%S",
                        format="%(asctime)s %(message)s")
    logging.getLogger("httpx").setLevel(logging.WARNING)  # no per-call lines
    port = int(os.environ.get("PORT", "8080"))
    log.info("pod=%s inventory=%s appRetries=%d", POD, INVENTORY_URL,
             APP_RETRIES)
    uvicorn.run(app, host="0.0.0.0", port=port, log_level="warning",
                access_log=False, timeout_graceful_shutdown=10)
