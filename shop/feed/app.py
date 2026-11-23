"""TekTutor Shop price feed: a small TCP service with a line protocol.

The feed speaks first. When a client connects, the server sends a
greeting line, then answers one command per line:

    PRICE <sku>   ->  PRICE <sku> <amount>
    QUIT          ->  BYE, and the server closes the connection

Many older protocols work this way, for example SMTP, FTP and MySQL.
Chapter 14 uses the feed to show what happens when the mesh waits for
the client to speak first.

Run the server:   python app.py serve [port]          (default 7070)
Ask for a price:  python app.py ask <host> <port> <sku>
"""
import asyncio
import os
import sys
import time

PRICES = {"SKU-1": "12.50", "SKU-2": "8.75", "SKU-7": "99.00"}
NAME = os.environ.get("FEED_NAME", "feed")
GREETING_TIMEOUT = 5.0     # seconds the client waits for the greeting


async def handle(reader, writer):
    peer = writer.get_extra_info("peername")
    print(f"connection from {peer[0]}:{peer[1]}", flush=True)
    try:
        writer.write(f"FEED 1.0 READY {NAME}\r\n".encode())
        await writer.drain()
        while line := await reader.readline():
            words = line.decode(errors="replace").split()
            if words[:1] == ["QUIT"]:
                writer.write(b"BYE\r\n")
                break
            if len(words) == 2 and words[0] == "PRICE":
                sku = words[1]
                price = PRICES.get(sku, "unknown")
                writer.write(f"PRICE {sku} {price}\r\n".encode())
            else:
                writer.write(b"ERR unknown command\r\n")
            await writer.drain()
        await writer.drain()
    except ConnectionError:
        print(f"connection from {peer[0]}:{peer[1]} lost", flush=True)
    writer.close()


async def serve(port):
    server = await asyncio.start_server(handle, "0.0.0.0", port)
    print(f"{NAME} listening on port {port}", flush=True)
    async with server:
        await server.serve_forever()


async def ask(host, port, sku):
    start = time.monotonic()
    try:
        reader, writer = await asyncio.open_connection(host, port)
    except OSError as err:
        print(f"cannot connect to {host}:{port}: {err}")
        return 1
    print(f"connected after {time.monotonic() - start:.3f}s")
    try:
        greeting = await asyncio.wait_for(reader.readline(), GREETING_TIMEOUT)
    except asyncio.TimeoutError:
        print(f"no greeting after {GREETING_TIMEOUT}s")
        writer.close()
        return 1
    print(f"greeting: {greeting.decode().strip()}")
    writer.write(f"PRICE {sku}\r\nQUIT\r\n".encode())
    await writer.drain()
    while line := await reader.readline():
        print(f"answer:   {line.decode().strip()}")
    print(f"done after {time.monotonic() - start:.3f}s")
    writer.close()
    return 0


def main():
    if len(sys.argv) >= 2 and sys.argv[1] == "serve":
        port = int(sys.argv[2]) if len(sys.argv) > 2 else 7070
        asyncio.run(serve(port))
    elif len(sys.argv) == 5 and sys.argv[1] == "ask":
        sys.exit(asyncio.run(ask(sys.argv[2], int(sys.argv[3]), sys.argv[4])))
    else:
        print(__doc__)
        sys.exit(2)


if __name__ == "__main__":
    main()
