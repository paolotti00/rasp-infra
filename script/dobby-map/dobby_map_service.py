#!/usr/bin/env python3
"""Localhost service: converts the Ecovacs (Dobby) SVG map from Home Assistant into a PNG.

GET /render?path=<entity_picture of image.dobby_map>  ->  writes OUT and returns "ok".
"""
import subprocess
import urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse, parse_qs

HA = "http://127.0.0.1:8123"
OUT = "/home/pi/homeassistant/www/dobby_map.png"
ALLOWED = "/api/image_proxy/image.dobby_map"


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        url = urlparse(self.path)
        path = (parse_qs(url.query).get("path") or [""])[0]
        if url.path != "/render" or not path.startswith(ALLOWED):
            return self._reply(400, "bad request")
        try:
            svg = urllib.request.urlopen(HA + path, timeout=15).read()
            png = subprocess.run(
                ["rsvg-convert", "-w", "800", "-b", "white"],
                input=svg, capture_output=True, check=True, timeout=30,
            ).stdout
            with open(OUT, "wb") as f:
                f.write(png)
            self._reply(200, "ok")
        except Exception as e:
            self._reply(500, str(e))

    def _reply(self, code, msg):
        self.send_response(code)
        self.end_headers()
        self.wfile.write(msg.encode())

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    HTTPServer(("127.0.0.1", 8765), Handler).serve_forever()
