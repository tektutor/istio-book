"""Small stand-ins for the Bookinfo services, for the local ambient lab.

One script plays every role. Each service answers JSON on port 9080:

    productpage  GET /productpage   calls reviews and shows its answer
    reviews      GET /reviews/0     v2 and v3 also call ratings
    ratings      GET /ratings/0     returns a fixed rating
    every role   GET /headers       returns the request headers it got

Usage: ROLE=reviews VERSION=v2 POD_NAME=reviews-v2-0 python3 bookinfo.py
"""
import json
import os
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROLE = os.environ["ROLE"]
VERSION = os.environ.get("VERSION", "v1")
POD = os.environ.get("POD_NAME", ROLE)
REVIEWS = os.environ.get("REVIEWS_URL", "http://10.96.10.11:9080")
RATINGS = os.environ.get("RATINGS_URL", "http://10.96.10.12:9080")


def call(url):
    """GET url and return its JSON, or the error as text."""
    try:
        with urllib.request.urlopen(url, timeout=5) as r:
            return json.load(r)
    except Exception as e:                                # noqa: BLE001
        return {"error": str(e)}


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"                         # keep-alive
    disable_nagle_algorithm = True                        # no 40 ms stalls

    def do_GET(self):
        if self.path == "/headers":
            body = dict(self.headers)
        elif ROLE == "productpage" and self.path.startswith("/productpage"):
            body = {"pod": POD, "reviews": call(f"{REVIEWS}/reviews/0")}
        elif ROLE == "reviews" and self.path.startswith("/reviews/"):
            body = {"pod": POD, "version": VERSION}
            if VERSION != "v1":
                body["ratings"] = call(f"{RATINGS}/ratings/0")
        elif ROLE == "ratings" and self.path.startswith("/ratings/"):
            body = {"pod": POD, "rating": 5}
        else:
            self.send_error(404)
            return
        data = (json.dumps(body) + "\n").encode()
        self.send_response(200)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *args):                         # quiet
        pass


ThreadingHTTPServer(("0.0.0.0", 9080), Handler).serve_forever()
