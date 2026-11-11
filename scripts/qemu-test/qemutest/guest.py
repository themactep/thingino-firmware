"""Command channel to the guest: SSH when available, serial fallback."""

import subprocess
from .config import SSH_OPTS
from .probes import until


class Guest:
    """Command channel to the guest: SSH when available, serial fallback.
    run() returns (rc, output); serial rc is parsed from an echo marker."""

    def __init__(self, ser):
        self.ser = ser
        self.ssh_target = None
        self.ssh_port = 22
        self.ssh_key = None
        self.ssh_ok = False

    def enable_ssh(self, addr, port, keyfile):
        self.ssh_target = addr
        self.ssh_port = port
        self.ssh_key = keyfile
        rc, out = self._ssh("echo sshok")
        self.ssh_ok = (rc == 0 and "sshok" in out)
        return self.ssh_ok

    def _ssh(self, cmd, timeout=20):
        addr = self.ssh_target
        if ":" in addr and "%" not in addr:
            pass  # plain global v6 is fine unbracketed for ssh CLI
        try:
            p = subprocess.run(
                ["ssh", "-p", str(self.ssh_port), "-i", self.ssh_key,
                 *SSH_OPTS, f"root@{addr}", cmd],
                capture_output=True, text=True, timeout=timeout)
            return p.returncode, p.stdout + p.stderr
        except subprocess.TimeoutExpired:
            return -1, "(ssh timeout)"

    def _serial(self, cmd, timeout=20):
        self.ser.read(0.2)                    # drain
        self.ser.write(cmd + "; echo __RC=$?\n")
        m, buf = self.ser.wait_for_re(r"__RC=(\d+)", timeout)
        if not m:
            return -1, buf
        text = buf[:m.start()]
        lines = text.split("\n")
        if lines and cmd[:20] in lines[0]:
            lines = lines[1:]                 # drop command echo
        return int(m.group(1)), "\n".join(lines)

    def reboot(self):
        """Ask the guest to reboot. Nothing is typed again until login()
        has seen a reset banner and a fresh prompt."""
        self.ser.read()                       # drop the buffered prompt
        self.ser.write("reboot\n")
        self.expect_reboot()

    def expect_reboot(self):
        """The guest is rebooting on its own (portal provisioning does
        this); same gating as reboot() without sending the command."""
        self.ser.state = "rebooting"
        self.ssh_ok = False                   # key is gone with the boot

    def run(self, cmd, timeout=20, via=None):
        if self.ser.state != "shell":
            return -1, f"(guest not at shell: {self.ser.state})"
        if via == "serial" or (via != "ssh" and not self.ssh_ok):
            return self._serial(cmd, timeout)
        if via == "ssh" or self.ssh_ok:
            return self._ssh(cmd, timeout)
        return self._serial(cmd, timeout)

    def run_until(self, cmd, ok, wait, every=2.0, **kw):
        """Re-run cmd until ok(output) holds or wait seconds pass.
        Returns the last output either way, for the check detail."""
        return until(lambda: self.run(cmd, **kw)[1], wait, every, ok)
