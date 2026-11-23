"""A stand-in for an external HTTPS API: it reports what arrived, so you
can see that the request left the proxy as TLS.

Usage: python3 partner_api.py <cert> <key> [port]     (default 18743)
"""
import http.server
import ssl
import sys

seen = {}


class Api(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        tls = self.connection.version()
        body = (f"partner api: path={self.path} tls={tls} "
                f"sni={seen.get('sni')}\n").encode()
        self.send_response(200)
        self.send_header("content-type", "text/plain")
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


def remember_sni(sock, name, ctx):
    seen["sni"] = name


cert, key = sys.argv[1], sys.argv[2]
port = int(sys.argv[3]) if len(sys.argv) > 3 else 18743
ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.load_cert_chain(cert, key)
ctx.sni_callback = remember_sni
server = http.server.HTTPServer(("127.0.0.1", port), Api)
server.socket = ctx.wrap_socket(server.socket, server_side=True)
server.serve_forever()
