"""Tests for the price feed. Run them with: pytest"""
import asyncio

import app


async def talk(lines):
    server = await asyncio.start_server(app.handle, "127.0.0.1", 0)
    port = server.sockets[0].getsockname()[1]
    reader, writer = await asyncio.open_connection("127.0.0.1", port)
    writer.write("".join(f"{line}\r\n" for line in lines).encode())
    await writer.drain()
    answer = (await reader.read()).decode().splitlines()
    writer.close()
    server.close()
    return answer


def test_the_server_speaks_first_and_answers_a_price():
    answer = asyncio.run(talk(["PRICE SKU-1", "QUIT"]))
    assert answer == ["FEED 1.0 READY feed", "PRICE SKU-1 12.50", "BYE"]


def test_unknown_commands_and_skus():
    answer = asyncio.run(talk(["HELLO", "PRICE SKU-9", "QUIT"]))
    assert answer[1:] == ["ERR unknown command", "PRICE SKU-9 unknown", "BYE"]
