# The lab's service: answers every GET with its pod name and, when the call
# came over mutual TLS, the caller's SPIFFE identity, which the sidecar
# passes in the x-forwarded-client-cert header.
import json, os, re, http.server

POD = os.environ.get("POD_NAME", "unknown")


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        xfcc = self.headers.get("x-forwarded-client-cert", "")
        match = re.search(r"URI=([^;,]+)", xfcc)                    # (1)
        body = json.dumps({"pod": POD,
                           "caller": match.group(1) if match else None})
        data = body.encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *args):                                   # (2)
        pass


port = int(os.environ.get("PORT", "8000"))
http.server.ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()
