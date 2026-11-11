"""Minimal QMP client."""

import json
import socket
import time


class Qmp:
    """Minimal QMP client over the unix socket."""

    def __init__(self, path):
        self.sock = None
        self.buf = b""
        deadline = time.time() + 10
        while time.time() < deadline:
            try:
                s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                s.connect(path)
                self.sock = s
                break
            except OSError:
                time.sleep(0.5)
        if not self.sock:
            raise RuntimeError(f"cannot connect QMP socket {path}")
        self.sock.settimeout(5)
        self._recv_obj()                      # greeting
        self.cmd("qmp_capabilities")

    def _recv_obj(self):
        while True:
            nl = self.buf.find(b"\n")
            if nl >= 0:
                line, self.buf = self.buf[:nl], self.buf[nl + 1:]
                if line.strip():
                    return json.loads(line)
                continue
            self.buf += self.sock.recv(65536)

    def cmd(self, command, **args):
        msg = {"execute": command}
        if args:
            msg["arguments"] = args
        self.sock.sendall((json.dumps(msg) + "\n").encode())
        while True:
            obj = self._recv_obj()
            if "event" in obj:
                continue
            if "error" in obj:
                raise RuntimeError(f"QMP {command}: {obj['error']}")
            return obj.get("return")

    def set_link(self, name, up):
        return self.cmd("set_link", name=name, up=up)

    def close(self):
        try:
            self.sock.close()
        except OSError:
            pass
