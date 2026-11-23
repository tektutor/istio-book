"""A small API that says which version answered, and can be slow on purpose.

The same program runs as version v1 and as version v2 of one service,
on your machine for the demo and in a cluster for Lab 35.3. It answers
every GET with a short JSON document, for example {"version": "v2"}.

Settings, from environment variables:
    VERSION        the version to report             (default v1)
    DELAY_SECONDS  seconds to wait before answering  (default 0)
    PORT           the port to listen on             (default 8080)
    HOST           the address to listen on          (default 0.0.0.0)
"""
import asyncio
import json
import os

VERSION = os.environ.get("VERSION", "v1")
DELAY = float(os.environ.get("DELAY_SECONDS", "0"))
PORT = int(os.environ.get("PORT", "8080"))
HOST = os.environ.get("HOST", "0.0.0.0")


def answer(body: dict) -> bytes:
    data = json.dumps(body) + "\n"
    return ("HTTP/1.1 200 OK\r\ncontent-type: application/json\r\n"
            f"content-length: {len(data)}\r\n\r\n{data}").encode()


async def handle(reader, writer):
    try:
        while True:                                  # (1)
            await reader.readuntil(b"\r\n\r\n")
            if DELAY:
                await asyncio.sleep(DELAY)           # (2)
            writer.write(answer({"version": VERSION}))
            await writer.drain()
    except (asyncio.IncompleteReadError, ConnectionError):
        pass                                         # (3)
    writer.close()


async def main():
    server = await asyncio.start_server(handle, HOST, PORT)
    print(f"{VERSION} listening on {HOST}:{PORT}, delay {DELAY}s", flush=True)
    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    asyncio.run(main())
