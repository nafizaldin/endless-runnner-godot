#!/usr/bin/env python3
"""Minimal static HTTP server with headers required by Godot Web (threaded build)."""

import os
import sys
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler

SERVE_ROOT = os.environ.get("SERVE_ROOT", "/srv/www")
HOST = os.environ.get("HOST", "0.0.0.0")
PORT = int(os.environ.get("PORT", "8080"))


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=SERVE_ROOT, **kwargs)

    def log_message(self, fmt, *args):
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))

    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cross-Origin-Resource-Policy", "same-origin")
        super().end_headers()


def main():
    os.chdir(SERVE_ROOT)

    Handler.extensions_map.update({
        ".js": "application/javascript",
        ".mjs": "application/javascript",
        ".wasm": "application/wasm",
        ".wasm.map": "application/json",
        ".json": "application/json",
        ".svg": "image/svg+xml",
        ".webp": "image/webp",
        ".wav": "audio/wav",
        ".mp3": "audio/mpeg",
        ".woff2": "font/woff2",
    })

    httpd = ThreadingHTTPServer((HOST, PORT), Handler)
    print("Serving %s on http://%s:%s/" % (SERVE_ROOT, HOST, PORT), flush=True)
    httpd.serve_forever()


if __name__ == "__main__":
    main()
