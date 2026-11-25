"""Small deterministic HTTP service used by the lab security scenarios."""

import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.error import HTTPError, URLError
from urllib.request import urlopen


ROLES = {"frontend", "api", "decoy"}


def handler_for(role, api_url):
    if role not in ROLES:
        raise ValueError(f"unsupported role: {role}")

    class Handler(BaseHTTPRequestHandler):
        server_version = "LabDemo"
        sys_version = ""

        def do_GET(self):
            if self.path == "/healthz":
                self.respond(200, {"status": "ok", "service": role})
            elif role == "api" and self.path == "/message":
                self.respond(200, {"message": "supply-chain-demo"})
            elif role == "frontend" and self.path == "/":
                try:
                    with urlopen(api_url, timeout=2) as upstream:
                        if upstream.status != 200:
                            raise URLError("upstream returned an unexpected status")
                        message = json.load(upstream)["message"]
                except (HTTPError, URLError, TimeoutError, ValueError, KeyError):
                    self.respond(502, {"error": "api unavailable"})
                    return
                self.respond(200, {"service": "frontend", "message": message})
            elif role == "decoy" and self.path == "/":
                self.respond(200, {"service": "decoy"})
            else:
                self.respond(404, {"error": "not found"})

        def respond(self, status, payload):
            body = json.dumps(payload, sort_keys=True).encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)

    return Handler


def main():
    role = os.environ.get("ROLE", "frontend")
    port = int(os.environ.get("PORT", "8080"))
    api_url = os.environ.get("API_URL", "http://api:8080/message")
    if not 1 <= port <= 65535:
        raise ValueError("PORT must be between 1 and 65535")
    server = ThreadingHTTPServer(("0.0.0.0", port), handler_for(role, api_url))
    try:
        server.serve_forever()
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
