import json
import threading
import unittest
from contextlib import contextmanager
from http.server import ThreadingHTTPServer
from urllib.error import HTTPError
from urllib.request import urlopen

from app import handler_for


@contextmanager
def service(role, api_url="http://127.0.0.1:1/message"):
    server = ThreadingHTTPServer(("127.0.0.1", 0), handler_for(role, api_url))
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        yield f"http://127.0.0.1:{server.server_port}"
    finally:
        server.shutdown()
        server.server_close()
        thread.join()


def get_json(url):
    with urlopen(url, timeout=3) as response:
        return response.status, json.load(response)


class AppTests(unittest.TestCase):
    def test_frontend_calls_api(self):
        with service("api") as api:
            with service("frontend", f"{api}/message") as frontend:
                self.assertEqual(get_json(f"{frontend}/"), (200, {
                    "service": "frontend", "message": "supply-chain-demo"
                }))
                self.assertEqual(get_json(f"{frontend}/healthz"), (200, {
                    "status": "ok", "service": "frontend"
                }))

    def test_frontend_reports_unavailable_api(self):
        with service("frontend") as frontend:
            with self.assertRaises(HTTPError) as error:
                get_json(f"{frontend}/")
            self.assertEqual(error.exception.code, 502)
            error.exception.close()

    def test_decoy_and_missing_route(self):
        with service("decoy") as decoy:
            self.assertEqual(get_json(f"{decoy}/"), (200, {"service": "decoy"}))
            with self.assertRaises(HTTPError) as error:
                get_json(f"{decoy}/message")
            self.assertEqual(error.exception.code, 404)
            error.exception.close()


if __name__ == "__main__":
    unittest.main()
