"""A stand-in for an HTTP server whose keep-alive timeout is short. It
answers every request on a connection, but when a request arrives after
the connection was idle for longer than the keep-alive, it closes the
connection without an answer. That is what a real server does when it
times out the connection at the moment the proxy reuses it.

Usage: python3 keepalive_server.py [port] [keep-alive seconds]
                                               (default 18401, 1.0)
Set HOST=0.0.0.0 to listen on every address, as a pod must.
"""
import os
import socket
import sys
import threading
import time

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 18401
KEEP_ALIVE = float(sys.argv[2]) if len(sys.argv) > 2 else 1.0
BODY = b'{"sku":"SKU-1","stock":42}\n'


def handle(conn):
    last = time.monotonic()
    buf = b""
    while True:
        try:
            chunk = conn.recv(65536)
        except OSError:
            break
        if not chunk:
            break
        if not buf and time.monotonic() - last > KEEP_ALIVE:     # (1)
            conn.close()
            return
        buf += chunk
        while b"\r\n\r\n" in buf:                                # (2)
            _, buf = buf.split(b"\r\n\r\n", 1)
            conn.sendall(b"HTTP/1.1 200 OK\r\ncontent-type: application/json"
                         b"\r\ncontent-length: " + str(len(BODY)).encode()
                         + b"\r\n\r\n" + BODY)
            last = time.monotonic()
    conn.close()


HOST = os.environ.get("HOST", "127.0.0.1")
server = socket.create_server((HOST, PORT))
while True:
    c, _ = server.accept()
    threading.Thread(target=handle, args=(c,), daemon=True).start()
