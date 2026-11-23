"""One HTTP server per zone, on loopback addresses; each answers with the
name of its zone. The file "down" next to this script lists failed zones,
one per line, as "<zone> 503" (the app answers 503) or "<zone> refuse"
(nothing listens, so connections are refused)."""
import http.server
import os
import threading
import time

ZONES = {"zone-a": "127.0.0.11", "zone-b": "127.0.0.12",
         "zone-c": "127.0.0.13", "dr-a": "127.0.0.14"}
DOWN = os.path.join(os.path.dirname(os.path.abspath(__file__)), "down")


def failures():
    try:
        with open(DOWN) as f:
            return dict(line.split() for line in f if line.strip())
    except FileNotFoundError:
        return {}


def handler(zone):
    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            code = 503 if failures().get(zone) == "503" else 200    # (1)
            body = (zone + "\n").encode()
            self.send_response(code)
            self.send_header("content-length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *args):
            pass
    return Handler


servers = {}


def start(zone):
    server = http.server.ThreadingHTTPServer((ZONES[zone], 9080),
                                             handler(zone))
    server.daemon_threads = True
    threading.Thread(target=server.serve_forever, daemon=True).start()
    servers[zone] = server


for zone in ZONES:
    start(zone)
while True:                                                          # (2)
    state = failures()
    for zone in ZONES:
        if state.get(zone) == "refuse" and zone in servers:
            server = servers.pop(zone)
            server.shutdown()
            server.server_close()
        elif state.get(zone) != "refuse" and zone not in servers:
            start(zone)
    time.sleep(0.1)
