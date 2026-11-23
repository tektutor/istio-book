"""The reports service of Lab 30.3: an API on one port, metrics on another.

    port 8080   GET /...       a JSON document, {"report": "<path>"}
    port 9100   GET /metrics   the request count, in the Prometheus format

Many real services look like this: the application framework serves its
metrics on a separate port, so that the API and the metrics can have
different access rules.
"""
import asyncio
import json

requests_total = 0


def answer(content_type: str, body: str) -> bytes:
    return (f"HTTP/1.1 200 OK\r\ncontent-type: {content_type}\r\n"
            f"content-length: {len(body)}\r\n\r\n{body}").encode()


async def serve(reader, writer, metrics: bool):
    global requests_total
    try:
        while True:                                  # keep-alive loop
            head = await reader.readuntil(b"\r\n\r\n")
            path = head.split(b" ", 2)[1].decode()
            if metrics:                              # (1)
                body = ("# TYPE reports_requests_total counter\n"
                        f"reports_requests_total {requests_total}\n")
                writer.write(answer("text/plain; version=0.0.4", body))
            else:
                requests_total += 1
                body = json.dumps({"report": path}) + "\n"
                writer.write(answer("application/json", body))
            await writer.drain()
    except (asyncio.IncompleteReadError, ConnectionError):
        pass
    writer.close()


async def main():
    api = await asyncio.start_server(
        lambda r, w: serve(r, w, metrics=False), "0.0.0.0", 8080)
    stats = await asyncio.start_server(
        lambda r, w: serve(r, w, metrics=True), "0.0.0.0", 9100)
    print("api on 8080, metrics on 9100", flush=True)
    async with api, stats:
        await asyncio.gather(api.serve_forever(), stats.serve_forever())


if __name__ == "__main__":
    asyncio.run(main())
