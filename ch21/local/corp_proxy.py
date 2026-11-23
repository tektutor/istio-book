"""A stand-in for a corporate HTTP proxy that accepts CONNECT requests.
It prints every CONNECT line it gets, opens the connection, and then
copies bytes in both directions without reading them.

Usage: python3 corp_proxy.py [port]                  (default 18728)
"""
import socket
import sys
import threading

# The lab has no DNS for these names, so the proxy maps them itself.
HOSTS = {"api.partner.tektutor.test": "127.0.0.1"}


def pipe(src, dst):
    try:
        while data := src.recv(65536):
            dst.sendall(data)
    except OSError:
        pass
    finally:
        dst.close()


def handle(client):
    head = b""
    while b"\r\n\r\n" not in head:
        chunk = client.recv(4096)
        if not chunk:
            client.close()
            return
        head += chunk
    first = head.split(b"\r\n")[0].decode()
    print(f"corp proxy: {first}", flush=True)                  # (1)
    method, target, _ = first.split(" ")
    host, port = target.rsplit(":", 1)
    if method != "CONNECT":
        client.sendall(b"HTTP/1.1 405 Method Not Allowed\r\n\r\n")
        client.close()
        return
    try:
        upstream = socket.create_connection((HOSTS.get(host, host),
                                             int(port)), timeout=5)
    except OSError:
        client.sendall(b"HTTP/1.1 502 Bad Gateway\r\n\r\n")
        client.close()
        return
    client.sendall(b"HTTP/1.1 200 Connection Established\r\n\r\n")  # (2)
    threading.Thread(target=pipe, args=(client, upstream),
                     daemon=True).start()
    pipe(upstream, client)


port = int(sys.argv[1]) if len(sys.argv) > 1 else 18728
server = socket.create_server(("127.0.0.1", port))
while True:
    conn, _ = server.accept()
    threading.Thread(target=handle, args=(conn,), daemon=True).start()
