"""The "where" service on a virtual machine: the same answer as the pods,
with the host name as the node and "vm" as the zone."""
import http.server
import json
import socket

BODY = json.dumps({"node": socket.gethostname(), "zone": "vm",
                   "pod": socket.gethostname()}).encode()


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(BODY)))
        self.end_headers()
        self.wfile.write(BODY)

    def log_message(self, *args):
        pass


http.server.ThreadingHTTPServer(("", 8080), Handler).serve_forever()
