"""A test server that misbehaves on purpose, to produce response flags.

    GET /ok/...     answers 200 at once
    GET /fail/...   answers 503 at once
    GET /slow/...   answers 200 after two seconds
    GET /close/...  reads the request and closes the connection without
                    an answer

Usage: python3 upstream.py [port]     (default 18986)
"""
import asyncio
import sys

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 18986


def answer(status: str, body: str) -> bytes:
    return (f"HTTP/1.1 {status}\r\ncontent-type: text/plain\r\n"
            f"content-length: {len(body)}\r\n\r\n{body}").encode()


async def handle(reader, writer):
    try:
        while True:                                  # keep-alive loop
            head = await reader.readuntil(b"\r\n\r\n")
            path = head.split(b" ", 2)[1].decode()
            if path.startswith("/close/"):           # (1)
                break
            if path.startswith("/slow/"):
                await asyncio.sleep(2)
            if path.startswith("/fail/"):
                writer.write(answer("503 Service Unavailable", "failed\n"))
            else:
                writer.write(answer("200 OK", "ok\n"))
            await writer.drain()
    except (asyncio.IncompleteReadError, ConnectionError):
        pass
    writer.close()


async def main():
    server = await asyncio.start_server(handle, "127.0.0.1", PORT)
    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    asyncio.run(main())
