"""qemu-dev gpio --serve: a live page of a session's pins.

The page replays the session's pin log (gpio.jsonl) and console, then
follows both as they grow, over Server-Sent Events. Its buttons drive
inputs, set ADC samples and pause the machine through QMP. Console lines
carry no virtual time: the page places them by when they arrive.
"""

import json
import os
import re
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

from .qmp import Qmp

PAGE = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                    "gpioview.html")
MARK = re.compile(r"QD[0-9a-f]{8}")


def serve(s, port, pins, clean, gpio_pin):
    trace = s.path("gpio.jsonl")
    meta = {"name": s.name, "model": s.info.get("model"),
            "machine": s.info.get("machine"), "pins": pins}

    def qmp(command, **args):
        q = Qmp(s.path("qmp"))
        try:
            return q.cmd(command, **args)
        finally:
            q.close()

    def drive(word, level):
        if not re.fullmatch(r"(?i)p[a-f]\d{1,2}|\d{1,3}", word):
            raise ValueError(f"not a pin: {word}")
        port, pin = gpio_pin(word)
        prop = f"in-p{chr(97 + port)}"
        cur = qmp("qom-get", path="/machine/soc/gpio", property=prop)
        qmp("qom-set", path="/machine/soc/gpio", property=prop,
            value=cur & ~(1 << pin) | level << pin)

    class Handler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def log_message(self, *args):
            pass

        def reply(self, code, body, ctype="application/json"):
            data = body if isinstance(body, bytes) else body.encode()
            self.send_response(code)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self):
            path = urlparse(self.path).path
            if path == "/":
                with open(PAGE, "rb") as f:
                    self.reply(200, f.read(), "text/html; charset=utf-8")
            elif path == "/meta":
                self.reply(200, json.dumps(meta))
            elif path == "/events":
                self.events()
            else:
                self.reply(404, '{"error":"not found"}')

        def do_POST(self):
            url = urlparse(self.path)
            q = {k: v[0] for k, v in parse_qs(url.query).items()}
            try:
                if url.path == "/drive":
                    drive(q["pin"], int(q["level"]) & 1)
                elif url.path == "/adc":
                    qmp("qom-set", path="/machine/soc/sadc",
                        property=f"aux{int(q['ch'])}", value=int(q["value"]))
                elif url.path in ("/stop", "/cont"):
                    qmp(url.path[1:])
                else:
                    return self.reply(404, '{"error":"not found"}')
            except (KeyError, ValueError, RuntimeError, OSError,
                    SystemExit) as e:
                return self.reply(400, json.dumps({"error": str(e)}))
            self.reply(200, "{}")

        def events(self):
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            gbuf, cbuf, quiet, first, echo = "", b"", 0.0, True, False
            try:
                with open(trace) as g, open(s.log, "rb") as c:
                    while True:
                        out = []
                        gbuf += g.read()
                        *lines, gbuf = gbuf.split("\n")
                        out += [f"event: gpio\ndata: {ln}\n\n"
                                for ln in lines if ln]
                        cbuf += c.read()
                        *raw, cbuf = cbuf.split(b"\n")
                        for ln in raw:
                            text = clean(ln.decode(errors="replace")).strip()
                            # qemu-dev's own command lines, echoed and
                            # wrapped, and their markers; their output stays
                            if "printf '\\n%s%s\\n' QD" in text:
                                echo = True
                            if echo:
                                echo = "E $?" not in text
                                continue
                            if text and not MARK.search(text):
                                out.append("event: console\ndata: "
                                           f"{json.dumps(text)}\n\n")
                        if first:
                            # the first pass read all logged so far
                            out.append("event: live\ndata: {}\n\n")
                            first = False
                        if out:
                            self.wfile.write("".join(out).encode())
                            self.wfile.flush()
                            quiet = time.time()
                        elif time.time() - quiet > 10:
                            self.wfile.write(b": still here\n\n")
                            self.wfile.flush()
                            quiet = time.time()
                        else:
                            time.sleep(0.1)
            except (BrokenPipeError, ConnectionResetError):
                pass

    httpd = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    httpd.daemon_threads = True
    print(f"http://127.0.0.1:{httpd.server_address[1]}/  "
          f"({s.name}; Ctrl-C stops)", flush=True)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        httpd.server_close()
