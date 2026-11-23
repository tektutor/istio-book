"""The TekTutor Shop inventory service.

It answers stock queries. You can also make it slow or make it fail
while it runs, so you can watch how the mesh handles bad responses.

    GET  /api/stock/{sku}  returns the stock level for one SKU
    GET  /admin/faults     shows the current fault settings
    POST /admin/faults     changes them: ?fail=50&delay=3s&code=503
    GET  /healthz          liveness and readiness probe
"""
import asyncio
import logging
import os
import random
import re
import time
from contextlib import asynccontextmanager

import uvicorn
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, PlainTextResponse

POD = os.environ.get("POD_NAME", "local")
log = logging.getLogger("inventory")


class Faults:                                            # (1)
    """The fault settings. Every request reads them; POST /admin/faults
    changes them while the service runs."""
    fail_percent = 0       # 0 to 100: share of requests that fail
    fail_code = 503        # HTTP status code for a failed request
    delay = 0.0            # seconds to wait before every answer


class JSONLine(JSONResponse):
    """JSON with a newline at the end, so curl output ends cleanly."""

    def render(self, content) -> bytes:
        return super().render(content) + b"\n"


@asynccontextmanager
async def lifespan(app):
    yield                   # the service runs here
    log.info("pod=%s stopped", POD)


faults = Faults()
app = FastAPI(default_response_class=JSONLine, lifespan=lifespan)


async def unless_caller_leaves(request: Request, work):   # (2)
    """Run work, but cancel it if the caller of this request goes away.
    The proxy closes the connection when its timeout fires."""
    task = asyncio.ensure_future(work)
    while not task.done():
        if await request.is_disconnected():
            task.cancel()
            break
        await asyncio.wait({task}, timeout=0.05)
    return await task      # raises CancelledError if it was cancelled


@app.get("/api/stock/{sku}")
async def stock(sku: str, request: Request):
    start = time.monotonic()
    # Envoy adds this header when the route counts attempts.
    attempt = request.headers.get("x-envoy-attempt-count", "-")  # (3)

    try:
        await unless_caller_leaves(request, asyncio.sleep(faults.delay))
    except asyncio.CancelledError:
        log_request(sku, attempt, "cancelled", start)
        return PlainTextResponse("caller went away\n", status_code=499)

    if random.randrange(100) < faults.fail_percent:
        log_request(sku, attempt, str(faults.fail_code), start)
        return PlainTextResponse("injected failure\n",
                                 status_code=faults.fail_code)
    log_request(sku, attempt, "200", start)
    return {"sku": sku, "available": 42, "pod": POD}


def log_request(sku, attempt, status, start):
    # Fields: pod, SKU, attempt number, status, time taken.
    log.info("%s %s attempt=%s status=%s %s", POD, sku, attempt, status,
             seconds(time.monotonic() - start))


@app.get("/admin/faults")
async def show_faults():
    return {"fail": faults.fail_percent, "code": faults.fail_code,
            "delay": seconds(faults.delay)}


@app.post("/admin/faults")                               # (4)
async def set_faults(fail: str = "0", code: str = "503", delay: str = "0s"):
    """Every parameter you leave out goes back to its default."""
    try:
        fail_percent, fail_code = int(fail), int(code)
        delay_s = parse_duration(delay)
    except ValueError:
        fail_percent, fail_code, delay_s = -1, 0, -1
    if not (0 <= fail_percent <= 100 and 400 <= fail_code <= 599
            and delay_s >= 0):
        return PlainTextResponse(
            "use fail=0..100, code=400..599, delay=1s or 500ms\n",
            status_code=400)
    faults.fail_percent, faults.fail_code = fail_percent, fail_code
    faults.delay = delay_s
    log.info("pod=%s faults set: fail=%d%% code=%d delay=%s",
             POD, fail_percent, fail_code, seconds(delay_s))
    return await show_faults()


@app.get("/healthz")
async def healthz():
    return PlainTextResponse("ok\n")


def parse_duration(text: str) -> float:
    """Read a duration such as 3s, 1.5s or 200ms, in seconds."""
    match = re.fullmatch(r"(\d+(?:\.\d+)?)(ms|s)", text)
    if not match:
        raise ValueError(text)
    value = float(match.group(1))
    return value / 1000 if match.group(2) == "ms" else value


def seconds(value: float) -> str:
    """Format a duration the short way: 0s, 250ms, 2s, 1.996s."""
    ms = round(value * 1000)
    if ms == 0:
        return "0s"
    if ms < 1000:
        return f"{ms}ms"
    return f"{ms / 1000:.3f}".rstrip("0").rstrip(".") + "s"


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, datefmt="%H:%M:%S",
                        format="%(asctime)s %(message)s")
    port = int(os.environ.get("PORT", "8080"))
    log.info("pod=%s listening on :%d", POD, port)
    # On SIGTERM, uvicorn stops taking new requests and lets the requests
    # in flight finish, for up to 10 seconds.
    uvicorn.run(app, host="0.0.0.0", port=port, log_level="warning",  # (5)
                access_log=False, timeout_graceful_shutdown=10)
