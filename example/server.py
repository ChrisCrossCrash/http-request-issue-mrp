#!/usr/bin/env python3
"""Minimal download server for the HTTPRequest MRP.

Serves GET /api/benchmark/download/<n>/ as exactly <n> zero bytes with a
Content-Length header — no gzip, no chunked transfer encoding — so each
HTTPRequest read is cleanly bounded by download_chunk_size.

    python server.py        # listens on 127.0.0.1:8927
"""

import re
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HOST = "127.0.0.1"
PORT = 8927
CHUNK = 65536  # bytes per write; avoids building the whole body in memory

# Tolerates a leading double slash, in case the client builds the URL from a
# base that already ends in "/".
_DOWNLOAD_PATH = re.compile(r"^/+api/benchmark/download/(\d+)/?$")


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"  # clean streamed Content-Length, no chunking

    def do_GET(self) -> None:
        match = _DOWNLOAD_PATH.match(self.path)
        if not match:
            self.send_response(404)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return

        num_bytes = int(match.group(1))
        self.send_response(200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", str(num_bytes))
        self.end_headers()

        chunk = b"\x00" * CHUNK
        remaining = num_bytes
        while remaining >= CHUNK:
            self.wfile.write(chunk)
            remaining -= CHUNK
        if remaining:
            self.wfile.write(b"\x00" * remaining)


if __name__ == "__main__":
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    print("Listening on http://%s:%d/  (Ctrl+C to stop)" % (HOST, PORT))
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down.")
