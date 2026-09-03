"""Serial console channel to the guest."""

import os
import re
import select
import time


class QemuSerial:
    """Interact with a QEMU guest over a serial pty. Everything read is
    teed to a transcript file for post-mortem."""

    def __init__(self, proc, pty_path, log_path=None):
        self.proc = proc
        self.fd = os.open(pty_path, os.O_RDWR | os.O_NONBLOCK)
        self.log = open(log_path, "wb", buffering=0) if log_path else None
        self._dsr_tail = b""
        # Where the guest is: "boot" until the first login, "shell" once a
        # prompt is confirmed, "rebooting" from a reboot request until the
        # next confirmed prompt. Commands only go out in "shell".
        self.state = "boot"

    def read(self, timeout=2.0):
        buf = b""
        while True:
            r, _, _ = select.select([self.fd], [], [], timeout)
            if r:
                chunk = os.read(self.fd, 4096)
                buf += chunk
                if self.log:
                    self.log.write(chunk)
                # The shell profile probes terminal size with ESC[6n and
                # reads the reply from the tty; unanswered, that read eats
                # the next command we type. Answer every probe.
                scan = self._dsr_tail + chunk
                for _ in range(scan.count(b"\x1b[6n")):
                    os.write(self.fd, b"\x1b[40;120R")
                self._dsr_tail = scan[-3:]
                timeout = 0.3
            else:
                break
        return buf.decode(errors="replace")

    def write(self, s):
        pace = float(os.environ.get("SERIAL_PACE_MS", "0") or 0)
        if pace > 0:
            for ch in s.encode():
                os.write(self.fd, bytes([ch]))
                time.sleep(pace / 1000.0)
        else:
            os.write(self.fd, s.encode())

    def cmd(self, c, wait=2):
        if self.state != "shell":
            return ""                       # never type into a dying shell
        self.write(c + "\n")
        time.sleep(wait)
        return self.read()

    def wait_for(self, pattern, timeout=120):
        buf = ""
        deadline = time.time() + timeout
        while time.time() < deadline:
            chunk = self.read(1.0)
            buf += chunk
            if pattern in buf:
                return True, buf
        return False, buf

    def wait_for_re(self, pattern, timeout=30):
        buf = ""
        deadline = time.time() + timeout
        while time.time() < deadline:
            buf += self.read(1.0)
            m = re.search(pattern, buf)
            if m:
                return m, buf
        return None, buf

    def login(self, timeout=120, passwords=("root",)):
        """Reach a root shell; True moves the state to "shell"."""
        ok = self._login(timeout, passwords)
        if ok:
            self.state = "shell"
        return ok

    def _login(self, timeout, passwords):
        # Test images set U-Boot env debug=1: the console getty spawns a
        # root shell directly, so a prompt may arrive instead of login:.
        buf = ""
        got_login = False
        deadline = time.time() + timeout
        # After a reboot the shell echoes one more prompt before it starts
        # tearing down; matching that stale prompt returns "logged in" while
        # the machine is actually on its way down (and any command we then
        # type lands in the next boot's U-Boot autoboot). While rebooting,
        # gate on a genuine reset banner so only a post-reboot prompt counts.
        booted = self.state != "rebooting"
        while time.time() < deadline:
            buf += self.read(1.0)
            plain = re.sub(r"\x1b\[[0-9;?]*[A-Za-z]", "", buf)
            if not booted:
                if re.search(r"Restarting system|U-Boot SPL|Starting kernel",
                             plain):
                    booted = True
                    buf = ""
                continue
            if re.search(r"root@[\w.-]+ \S*# ", plain):
                time.sleep(1)
                self.read()
                return True
            if "login:" in plain:
                got_login = True
                break
        if not got_login:
            return False
        for pw in passwords:
            self.write("root\n")
            self.wait_for("Password:", 5)
            self.write(pw + "\n")
            m, out = self.wait_for_re(
                r"(change your password|Login incorrect|[#\$] )", 15)
            if m and "change your password" in m.group(1):
                self.wait_for("Password:", 5)
                self.write("\x03")
                time.sleep(3)
                self.read()
                return True
            if m and m.group(1) != "Login incorrect":
                # Let the shell profile finish (its size probe reads the
                # tty); typing into that window loses the first command.
                time.sleep(1)
                self.read()
                return True
            # wrong password: wait for the next login prompt and retry
            self.wait_for("login:", 10)
        return False

    def close(self):
        os.close(self.fd)
        if self.log:
            self.log.close()
