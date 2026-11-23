"""A tiny backend for the TLS demo: it answers with the client
certificate details that the gateway forwarded in the header
x-forwarded-client-cert, without the certificate itself.

Usage: python3 echo.py [port]          (default 18080)
"""
import http.server
import sys


class Echo(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        xfcc = self.headers.get("x-forwarded-client-cert", "")
        # Keep Subject, URI and DNS; the Cert field is long PEM text.
        parts = [p for p in xfcc.split(";") if not p.startswith("Cert=")]
        body = ("client: " + (";".join(parts) or "none") + "\n").encode()
        self.send_response(200)
        self.send_header("content-type", "text/plain")
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


port = int(sys.argv[1]) if len(sys.argv) > 1 else 18080
http.server.HTTPServer(("127.0.0.1", port), Echo).serve_forever()
