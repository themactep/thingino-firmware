#!/usr/bin/env python3
"""Record exactly one upload request and answer 201.

Used by the send2train tests to look at what the camera actually puts on the
wire: the header set, the multipart part name, and whether any host identity or
local path leaked into it.
"""

import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer


class Recorder(BaseHTTPRequestHandler):
    output = ""
    port_file = ""

    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0") or 0)
        body = self.rfile.read(length)
        record = {
            "method": self.command,
            "path": self.path,
            "headers": {key.lower(): value for key, value in self.headers.items()},
            "body": body.decode("latin-1"),
        }
        with open(self.output, "w", encoding="utf-8") as handle:
            json.dump(record, handle)
        self.send_response(201)
        self.send_header("Content-Length", "0")
        self.end_headers()
        self.close_connection = True

    def log_message(self, fmt, *args):
        return


def main():
    Recorder.output = sys.argv[1]
    Recorder.port_file = sys.argv[2]
    server = HTTPServer(("127.0.0.1", 0), Recorder)
    with open(Recorder.port_file, "w", encoding="utf-8") as handle:
        handle.write(str(server.server_address[1]))
    server.serve_forever()


if __name__ == "__main__":
    main()
