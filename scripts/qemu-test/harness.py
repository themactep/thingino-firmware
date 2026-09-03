#!/usr/bin/env -S python3 -u
"""
QEMU test harness for thingino firmware images.

Boots a firmware image in QEMU, logs in via serial, and runs assertions
against the running system. Supports three device modalities:

  wifi     - WiFi-only camera (portal mode, provisioning)
  eth      - Ethernet-only camera (wired web UI)
  ethwifi  - Ethernet + WiFi camera (wired takes priority)

and two network backends:

  slirp    - QEMU user networking with host port forwards (default)
  tap      - host tap + dnsmasq lab: real DHCPv4, RA/SLAAC, stateful
             DHCPv6, DNS, NTP, syslog, mDNS, WS-Discovery (needs root)

Usage:
  python3 harness.py --image <path> --soc <t31x|t10n|...> --mode <wifi|eth|ethwifi>

Exit code 0 = all tests pass, 1 = test failure, 2 = boot failure.
"""

import argparse
import json
import os
import re
import select
import shutil
import signal
import socket
import subprocess
import sys
import time

SOC_MACHINES = {
    "t10":  ("ingenic-t10",  64),
    "t10n": ("ingenic-t10",  64),
    "t20":  ("ingenic-t20",  128),
    "t20x": ("ingenic-t20",  128),
    "t21":  ("ingenic-t21",  64),
    "t21n": ("ingenic-t21",  64),
    "t23":  ("ingenic-t23",  64),
    "t23n": ("ingenic-t23",  64),
    "t30":  ("ingenic-t30",  128),
    "t30x": ("ingenic-t30",  128),
    "t31":  ("ingenic-t31",  128),
    "t31x": ("ingenic-t31",  128),
    "t32":  ("ingenic-t32",  256),
    "t32nq":("ingenic-t32",  256),
    "t40":  ("ingenic-t40",  256),
    "t40nn":("ingenic-t40",  256),
    "t41":  ("ingenic-t41",  256),
    "t41nq":("ingenic-t41",  256),
    "a1":   ("ingenic-a1",   256),
    "a1n":  ("ingenic-a1",   256),
}

PORTAL_PORT = 19080
WEBUI_PORT  = 19080
SSH_FWD_PORT = 19022

SSH_OPTS = ["-o", "StrictHostKeyChecking=no",
            "-o", "UserKnownHostsFile=/dev/null",
            "-o", "ConnectTimeout=5",
            "-o", "LogLevel=ERROR",
            "-o", "PasswordAuthentication=no",
            "-o", "BatchMode=yes"]


class QemuSerial:
    """Interact with a QEMU guest over a serial pty. Everything read is
    teed to a transcript file for post-mortem."""

    def __init__(self, proc, pty_path, log_path=None):
        self.proc = proc
        self.fd = os.open(pty_path, os.O_RDWR | os.O_NONBLOCK)
        self.log = open(log_path, "wb", buffering=0) if log_path else None
        self._dsr_tail = b""

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

    def login(self, timeout=120, passwords=("root",), expect_reboot=False):
        # Test images set U-Boot env debug=1: the console getty spawns a
        # root shell directly, so a prompt may arrive instead of login:.
        buf = ""
        got_login = False
        deadline = time.time() + timeout
        # After a reboot the shell echoes one more prompt before it starts
        # tearing down; matching that stale prompt returns "logged in" while
        # the machine is actually on its way down (and any command we then
        # type lands in the next boot's U-Boot autoboot). Gate on a genuine
        # reset banner first so only a post-reboot prompt counts.
        booted = not expect_reboot
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

    def run(self, cmd, timeout=20, via=None):
        if via == "serial" or (via != "ssh" and not self.ssh_ok):
            return self._serial(cmd, timeout)
        if via == "ssh" or self.ssh_ok:
            return self._ssh(cmd, timeout)
        return self._serial(cmd, timeout)


def find_qemu():
    candidates = [
        os.environ.get("QEMU_BIN", ""),
        shutil.which("qemu-system-mipsel") or "",
    ]
    for c in candidates:
        if c and os.path.isfile(c) and os.access(c, os.X_OK):
            return c
    sys.exit("Cannot find qemu-system-mipsel (set QEMU_BIN or use run.sh)")


def start_qemu(qemu, image, machine, ram_mb, net, report_dir, tap_if="qtap0"):
    # /tmp keeps the path under the 108-char unix socket limit
    qmp_path = f"/tmp/qemu-test-{os.getpid()}.qmp"
    args = [
        qemu, "-M", machine, "-m", f"{ram_mb}M",
        "-display", "none",
        "-serial", "null", "-serial", "pty",
        "-qmp", f"unix:{qmp_path},server,nowait",
        "-drive", f"file={image},format=raw,if=none,id=flash0",
    ]
    if net == "tap":
        args += ["-netdev",
                 f"tap,id=n0,ifname={tap_if},script=no,downscript=no"]
    else:
        args += [
            "-netdev", f"user,id=n0,"
            f"hostfwd=tcp::{PORTAL_PORT}-172.16.0.1:80,"
            f"hostfwd=tcp::{WEBUI_PORT + 1}-:80,"
            f"hostfwd=tcp::{WEBUI_PORT + 2}-:443,"
            f"hostfwd=tcp::{SSH_FWD_PORT}-:22",
        ]

    stdout_path = f"/tmp/qemu-test-{os.getpid()}.stdout"
    stdout_fh = open(stdout_path, "w+")
    stderr_fh = open(os.path.join(report_dir, "qemu-stderr.log"), "w")
    proc = subprocess.Popen(
        args,
        stdin=subprocess.DEVNULL,
        stdout=stdout_fh,
        stderr=stderr_fh,
    )

    m = None
    for _ in range(10):
        time.sleep(1)
        stdout_fh.flush()
        stdout_fh.seek(0)
        out = stdout_fh.read()
        m = re.search(r"redirected to (/dev/pts/\d+)", out)
        if m:
            break
        if proc.poll() is not None:
            stderr_fh.flush()
            err = open(os.path.join(report_dir, "qemu-stderr.log")).read()
            sys.exit(f"QEMU failed to start: {out[:300]} {err[:300]}")
    stdout_fh.close()
    if not m:
        proc.terminate()
        sys.exit("Could not find pty in QEMU output (searched 10s)")
    os.unlink(stdout_path)

    return proc, m.group(1), qmp_path


class TestResult:
    def __init__(self):
        self.passed = []
        self.failed = []
        self.xfailed = []
        self.skipped = []
        self.results = []

    def ok(self, name, detail=""):
        self.passed.append(name)
        self.results.append({"name": name, "pass": True, "detail": detail})
        print(f"  PASS  {name}" + (f"  ({detail})" if detail else ""))

    def fail(self, name, detail=""):
        self.failed.append(name)
        self.results.append({"name": name, "pass": False, "detail": detail})
        print(f"  FAIL  {name}" + (f"  ({detail})" if detail else ""))

    def check(self, name, condition, detail=""):
        if condition:
            self.ok(name, detail)
        else:
            self.fail(name, detail)

    def xfail(self, name, condition, reason=""):
        """Known-gap test: failing is expected and doesn't fail the run,
        passing is celebrated."""
        if condition:
            self.passed.append(name)
            self.results.append({"name": name, "pass": True,
                                 "detail": f"XPASS: {reason}", "xfail": True})
            print(f"  XPASS {name}  ({reason})")
        else:
            self.xfailed.append(name)
            self.results.append({"name": name, "pass": False,
                                 "detail": f"expected: {reason}", "xfail": True})
            print(f"  XFAIL {name}  ({reason})")

    def skip(self, name, reason=""):
        self.skipped.append(name)
        self.results.append({"name": name, "pass": True, "skip": True,
                             "detail": f"skipped: {reason}"})
        print(f"  SKIP  {name}  ({reason})")

    def summary(self):
        total = len(self.passed) + len(self.failed)
        print(f"\n{'=' * 50}")
        print(f"Results: {len(self.passed)}/{total} passed"
              + (f", {len(self.xfailed)} xfail" if self.xfailed else "")
              + (f", {len(self.skipped)} skipped" if self.skipped else ""))
        if self.failed:
            print(f"Failed:  {', '.join(self.failed)}")
        return len(self.failed) == 0

    def save_json(self, path):
        with open(path, "w") as f:
            json.dump(self.results, f, indent=2)
        print(f"Results saved to {path}")


# ── Common test suites ───────────────────────────────────────

def test_boot(guest, res, meta):
    rc, out = guest.run("cat /proc/version")
    res.check("kernel_booted", "Linux" in out)
    m = re.search(r"Linux version (\S+)", out)
    if m:
        meta["kernel"] = m.group(1)

    rc, out = guest.run("uptime")
    res.check("init_complete", "load average" in out)

    rc, out = guest.run("ps | wc -l")
    try:
        nproc = int("".join(c for c in out.split("\n")[-1] if c.isdigit()) or
                    "".join(c for c in out if c.isdigit()))
        res.check("processes_running", nproc > 10, f"{nproc} processes")
    except ValueError:
        res.fail("processes_running", "could not parse ps output")


def test_services(guest, res, mode):
    rc, out = guest.run("ps w")
    res.check("dropbear_running", "dropbear" in out)
    res.check("syslogd_running", "syslogd" in out)
    if mode == "wifi":
        res.check("wpa_supplicant_running", "wpa_supplicant" in out)


def test_health(guest, res):
    """Kernel and system health gates."""
    rc, out = guest.run("dmesg", timeout=30)
    bad = re.findall(r"(Oops|BUG:|Kernel panic|Unable to handle)", out)
    # "Call Trace" is fatal unless it is the ingenic-sdk sensor probe
    # diagnostic dump (no sensor on QEMU's auto-NACK I2C, expected).
    lines = out.split("\n")
    benign = 0
    for i, line in enumerate(lines):
        if "Call Trace" in line:
            ctx = "\n".join(lines[max(0, i - 10):i])
            if re.search(r"is not an? \w+ chip", ctx):
                benign += 1
            else:
                bad.append("Call Trace")
    res.check("dmesg_no_oops", not bad,
              f"{len(bad)} hits: {bad[:3]}" if bad
              else (f"{benign} benign sensor-probe traces" if benign else ""))

    modbad = re.findall(r"(version magic|unknown symbol|disagrees about)",
                        out, re.IGNORECASE)
    res.check("dmesg_modules_clean", not modbad,
              f"{modbad[:3]}" if modbad else "")

    rc, out = guest.run("logread 2>/dev/null | tail -n 300 || "
                        "tail -n 300 /var/log/messages 2>/dev/null", timeout=20)
    seg = re.findall(r"(segfault|SIGSEGV|core dumped)", out, re.IGNORECASE)
    res.check("syslog_no_segfault", not seg, f"{seg[:3]}" if seg else "")

    rc, out = guest.run("cat /proc/meminfo")
    free = 0
    for key in ("MemFree", "Buffers", "Cached"):
        m = re.search(rf"{key}:\s+(\d+)", out)
        if m:
            free += int(m.group(1))
    free_mb = free // 1024
    res.check("memory_floor", free_mb >= 16, f"{free_mb} MB reclaimable")


def setup_ssh(guest, ser, res, report_dir, addr, port=22):
    """Install an ephemeral pubkey via serial, then switch to SSH."""
    key = os.path.join(report_dir, "id_ed25519")
    for p in (key, key + ".pub"):
        if os.path.exists(p):
            os.unlink(p)
    subprocess.run(["ssh-keygen", "-t", "ed25519", "-N", "", "-q",
                    "-f", key], check=True)
    pub = open(key + ".pub").read().strip()
    ser.cmd("mkdir -p /root/.ssh && chmod 700 /root/.ssh", 1)
    ser.cmd(f"echo '{pub}' > /root/.ssh/authorized_keys", 1)
    ok = guest.enable_ssh(addr, port, key)
    res.check("ssh_channel", ok, f"root@{addr}:{port}")
    return ok


# ── WiFi suites (slirp) ──────────────────────────────────────

def test_wifi_portal(guest, res):
    # The portal is deferred behind the wired-uplink probe and its radio
    # prescan, so it can trail login by tens of seconds. Wait for the AP.
    deadline = time.time() + 120
    while time.time() < deadline:
        rc, out = guest.run("wpa_cli -i wlan0 status 2>/dev/null")
        if "mode=AP" in out:
            break
        time.sleep(3)
    res.check("wifi_ap_mode", "mode=AP" in out)
    res.check("wifi_ssid_set", "ssid=THINGINO-" in out)

    rc, out = guest.run("ip addr show wlan0")
    res.check("wlan0_has_ip", "172.16.0.1" in out)

    # The portal-mode uhttpd restart trails the AP by several seconds
    deadline = time.time() + 60
    while time.time() < deadline:
        rc, out = guest.run(
            "curl -s -o /tmp/_portal -w '%{http_code}:%{size_download}' "
            "http://172.16.0.1/", timeout=15)
        if "200:" in out:
            break
        time.sleep(3)
    res.check("portal_http_200", "200:" in out)
    m = re.search(r"200:(\d+)", out)
    portal_bytes = int(m.group(1)) if m else 0
    res.check("portal_serves_html", portal_bytes > 100, f"{portal_bytes} bytes")

    rc, out = guest.run("cat /run/portal_mode 2>&1")
    res.check("portal_mode_flag", "No such file" not in out)


def test_wifi_modules(guest, res):
    rc, out = guest.run("lsmod")
    res.check("hwsim_loaded", "mac80211_hwsim" in out)

    rc, out = guest.run("cat /proc/net/dev")
    res.check("wlan0_exists", "wlan0" in out)
    res.check("wlan1_exists", "wlan1" in out)


def test_wifi_bridge_setup(guest, res):
    """Set up eth0 for SLIRP bridge (WiFi-only profile with GMAC driver)."""
    guest.run("ip link set eth0 up", timeout=8)
    # The a1 xgmac model loses a few RX frames right after ifup, so give
    # the exchange more rounds than the udhcpc default.
    rc, out = guest.run("udhcpc -i eth0 -n -q -t 8 -T 3 2>&1", timeout=40)
    got_ip = "obtained" in out.lower() or "lease of" in out.lower()
    res.check("bridge_eth0_dhcp", got_ip)

    guest.run("echo 1 > /proc/sys/net/ipv4/ip_forward")
    rc, out = guest.run("cat /proc/sys/net/ipv4/ip_forward")
    res.check("bridge_ip_forward", "1" in out)


def test_provision_reboot_sta(ser, guest, res, report_dir, qmp=None,
                              timeout=240):
    """After portal submit: wait for reboot, set up fake AP, verify STA."""
    print("\n── Post-provision reboot ──")
    print("  Waiting for guest reboot...")
    # Drop the SLIRP link for the STA boot: the qemu profile has a GMAC
    # that real WiFi-only cameras lack, and an instant SLIRP lease on
    # eth0 makes S40wired-gateway kill WiFi as "wired uplink present".
    if qmp:
        qmp.set_link("n0", False)
    time.sleep(3)
    # Provisioning set the root password (playwright fills TestPass1)
    if not ser.login(timeout, passwords=("TestPass1", "root")):
        if warm_reset_timer_wedge(report_dir):
            res.xfail("reboot_complete", False,
                      "QEMU warm-reset timer wedge (fork bug)")
        else:
            res.fail("reboot_complete", "no login prompt after reboot")
        if qmp:
            qmp.set_link("n0", True)
        return
    res.ok("reboot_complete")
    guest.ssh_ok = False                      # key not reinstalled after reboot

    # With the debug=1 console there is no login step, so verify the
    # provisioned password against the shadow hash on the guest.
    rc, out = guest.run(
        "h=$(grep '^root:' /etc/shadow | cut -d: -f2); "
        "t=$(echo \"$h\" | cut -d'$' -f2); "
        "s=$(echo \"$h\" | cut -d'$' -f3); "
        "case \"$t\" in 1) m=md5;; 5) m=sha256;; 6) m=sha512;; *) m='';; esac; "
        "if [ -n \"$m\" ] && "
        "[ \"$(mkpasswd -m $m -S \"$s\" TestPass1)\" = \"$h\" ]; "
        "then echo PWMATCH=yes; else echo PWMATCH=no; fi", timeout=15)
    res.check("provisioned_password_set", "PWMATCH=yes" in out,
              "root shadow hash matches provisioned password")

    rc, out = guest.run("hostname")
    res.check("saved_hostname", "qemu-test" in out,
              "provisioned hostname persisted")

    rc, out = guest.run("cat /etc/wpa_supplicant.conf 2>/dev/null")
    res.check("saved_wpa_conf", "TestNetwork" in out)

    print("  Seeding entropy from DTRNG...")
    guest.run("devmem 0x10072000 32 0x1")
    guest.run("for i in $(seq 1 20); do "
              "devmem 0x10072004 32 | sed 's/0x//' | "
              "xxd -r -p >> /dev/urandom; done", timeout=15)

    print("  Setting up fake AP on wlan1 (WPA-PSK)...")
    ser.cmd("cat > /tmp/fake_ap.conf << 'APEOF'\n"
            "ctrl_interface=/var/run/wpa_fakeap\n"
            "network={\n"
            '    ssid="TestNetwork"\n'
            "    mode=2\n"
            "    key_mgmt=WPA-PSK\n"
            '    psk="testpass123"\n'
            "    frequency=2437\n"
            "}\n"
            "APEOF")
    guest.run("wpa_supplicant -B -i wlan1 -c /tmp/fake_ap.conf", timeout=10)
    time.sleep(3)
    guest.run("ip addr add 192.168.1.1/24 dev wlan1")

    rc, out = guest.run(
        "wpa_cli -i wlan1 -p /var/run/wpa_fakeap status | grep mode")
    res.check("fake_ap_running", "mode=AP" in out)

    # Thingino configures ap_scan=2 for vendor WiFi chips; hwsim's
    # nl80211 driver needs ap_scan=1 to scan and associate normally
    # (wpa itself warns about the combination at startup).
    guest.run("wpa_cli -i wlan0 ap_scan 1")
    print("  Triggering wlan0 rescan...")
    guest.run("wpa_cli -i wlan0 scan")
    time.sleep(15)

    connected = False
    for attempt in range(7):
        rc, out = guest.run("wpa_cli -i wlan0 status")
        if "wpa_state=COMPLETED" in out and "TestNetwork" in out:
            connected = True
            break
        print(f"  Scan attempt {attempt + 1}...")
        guest.run("wpa_cli -i wlan0 scan")
        time.sleep(10)
    res.check("sta_connected_to_ap", connected,
              "wlan0 should connect to TestNetwork via WPA-PSK")

    if connected:
        guest.run("ip addr add 192.168.1.100/24 dev wlan0 2>/dev/null")
        rc, out = guest.run("ping -c 3 -W 2 192.168.1.1", timeout=15)
        res.check("sta_ping_ap",
                  "3 packets received" in out or "bytes from" in out)

    if qmp:
        qmp.set_link("n0", True)

    # The provisioned password must open the web UI. Re-bridge eth0 for
    # the slirp forward and drive the login form, capturing the login
    # screen and the logged-in page for the report.
    import urllib.request
    time.sleep(2)
    # Static bridge config: a fresh DHCP exchange after the reboot gets
    # the next slirp address, but the host forwards point at the slirp
    # default (10.0.2.15).
    guest.run("ip link set eth0 up", timeout=8)
    guest.run("ip addr flush dev eth0; ip addr add 10.0.2.15/24 dev eth0; "
              "ip route add default via 10.0.2.2 2>/dev/null; true",
              timeout=10)
    # The MAC is regenerated every boot; one ping refreshes slirp's ARP
    # entry for 10.0.2.15, which otherwise points the host forwards at
    # the previous boot's MAC until it expires.
    guest.run("ping -c 1 -W 2 10.0.2.2", timeout=10)
    webui_up = False
    deadline = time.time() + 45
    while time.time() < deadline:
        try:
            urllib.request.urlopen(
                f"http://localhost:{WEBUI_PORT + 1}/", timeout=3)
            webui_up = True
            break
        except Exception:
            time.sleep(2)
    res.check("webui_up_after_reboot", webui_up)
    if webui_up:
        run_playwright(res, report_dir, "webui-login", {
            "WEBUI_URL": f"http://localhost:{WEBUI_PORT + 1}",
            "WEBUI_PORT": str(WEBUI_PORT + 1),
            "WEBUI_LOGIN": "1",
            "WEBUI_PASS": "TestPass1",
            "SKIP_PORTAL": "1",
            "SKIP_WEBUI": "1",
            "SKIP_PROVISION": "1",
        }, check_name="webui_login_screens")


def test_host_portal_access(res):
    import urllib.request
    try:
        req = urllib.request.urlopen(
            f"http://localhost:{PORTAL_PORT}/", timeout=5)
        body = req.read(1024).decode(errors="replace")
        res.check("host_portal_reachable", req.status == 200)
        res.check("host_portal_content",
                  "Thingino" in body or "<!DOCTYPE" in body)
    except Exception as e:
        res.fail("host_portal_reachable", str(e))


def test_host_webui_access(res):
    import urllib.request
    try:
        req = urllib.request.urlopen(
            f"http://localhost:{WEBUI_PORT + 1}/", timeout=5)
        body = req.read(1024).decode(errors="replace")
        res.check("host_webui_reachable", req.status == 200)
        res.check("host_webui_content", "<!DOCTYPE" in body)
    except Exception as e:
        res.fail("host_webui_reachable", str(e))


# ── Ethernet suites ──────────────────────────────────────────

def test_ethernet(guest, res, lab=None):
    ok = False
    out = ""
    deadline = time.time() + 45
    while time.time() < deadline:
        rc, out = guest.run("ip addr show eth0")
        if "inet " in out:
            ok = True
            break
        time.sleep(2)
    res.check("eth0_has_ip", ok, out.strip()[:80])

    rc, out = guest.run("ip route")
    res.check("default_route_exists", "default" in out)


def test_webui(guest, res):
    rc, out = guest.run(
        "curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1/", timeout=15)
    res.check("webui_http_200", "200" in out)

    rc, out = guest.run("curl -s http://127.0.0.1/ | head -3", timeout=15)
    res.check("webui_serves_html", "<!DOCTYPE" in out)
    res.check("webui_not_portal",
              "portal" not in out.lower() or "preview" in out.lower())


def test_ethwifi_behavior(guest, res):
    """Wired takeover: S40wired-gateway stops the portal, kills wpa,
    and unloads the WLAN module once a wired uplink exists."""
    rc, out = guest.run("cat /run/portal_mode 2>&1")
    res.check("portal_mode_off", "No such file" in out)

    rc, out = guest.run("wpa_cli -i wlan0 status 2>&1")
    wifi_dead = ("INTERFACE_DISABLED" in out or "not found" in out.lower()
                 or "Failed" in out)
    res.check("wifi_stopped_by_ethernet", wifi_dead,
              "wired uplink should disable WiFi")

    rc, out = guest.run("lsmod")
    res.check("wifi_module_unloaded", "mac80211_hwsim" not in out,
              "wired-gateway rmmods the WLAN module")

    rc, out = guest.run("cat /proc/net/dev")
    res.check("wlan_ifaces_gone", "wlan0" not in out)


# ── tap-mode network suites ──────────────────────────────────

def get_guest_addrs(guest):
    """Return dict of guest eth0 addresses:
    v4 [addr], v6_ll [addr], v6_global [(addr, prefixlen)]."""
    addrs = {"v4": [], "v6_ll": [], "v6_global": []}
    rc, out = guest.run("ip addr show eth0")
    for m in re.finditer(r"inet (\d+\.\d+\.\d+\.\d+)/", out):
        addrs["v4"].append(m.group(1))
    for m in re.finditer(r"inet6 ([0-9a-f:]+)/(\d+) scope (\w+)", out):
        addr, plen, scope = m.groups()
        if scope == "link":
            addrs["v6_ll"].append(addr)
        elif scope == "global":
            addrs["v6_global"].append((addr, int(plen)))
    return addrs


def in_dhcpv6_range(addr):
    m = re.match(r"fd00:5c1::([0-9a-f]{1,4})$", addr)
    return bool(m and 0x100 <= int(m.group(1), 16) <= 0x1ff)


def test_ipv4_dhcp(guest, res, lab):
    """DHCPv4 against the host dnsmasq."""
    ok = False
    deadline = time.time() + 60
    while time.time() < deadline:
        addrs = get_guest_addrs(guest)
        if any(a.startswith("192.168.100.") for a in addrs["v4"]):
            ok = True
            break
        time.sleep(2)
    res.check("dhcp4_lease", ok,
              ", ".join(addrs["v4"]) if addrs["v4"] else "no v4 addr")

    rc, out = guest.run("ip -4 route")
    res.check("dhcp4_default_route", "default via 192.168.100.1" in out)
    res.check("dhcp4_wired_metric", bool(
        re.search(r"default via 192\.168\.100\.1 dev eth0\s+metric 100", out)),
        "wired metric 100")

    rc, out = guest.run("cat /etc/resolv.conf")
    res.check("dhcp4_dns_in_resolv", "192.168.100.1" in out)

    lease = lab.wait_lease(want_v4=True, timeout=10)
    res.check("dhcp4_server_lease", lease is not None,
              f"{lease['addr']} hostname={lease['hostname']}" if lease else "")
    return addrs["v4"][0] if addrs["v4"] else None


def test_ipv6(guest, res, lab):
    """Link-local, DAD, SLAAC, DHCPv6, RDNSS."""
    ll = None
    deadline = time.time() + 30
    while time.time() < deadline:
        addrs = get_guest_addrs(guest)
        if addrs["v6_ll"]:
            ll = addrs["v6_ll"][0]
            break
        time.sleep(2)
    res.check("ipv6_lladdr", ll is not None, ll or "no fe80 on eth0")

    rc, out = guest.run("ip -6 addr show eth0")
    res.check("ipv6_dad_ok",
              "tentative" not in out and "dadfailed" not in out)

    if ll:
        res.check("ipv6_host_ping_ll", lab.ping(ll, v6=True, link_local=True),
                  f"ping {ll}%{lab.tap}")

    # SLAAC address: /64 from the RA prefix with a full interface id
    # (the DHCPv6 IA_NA lease is a /128 from the ::100-::1ff pool).
    slaac = None
    deadline = time.time() + 45
    while time.time() < deadline:
        addrs = get_guest_addrs(guest)
        for a, plen in addrs["v6_global"]:
            if (a.startswith("fd00:5c1:") and plen == 64
                    and not in_dhcpv6_range(a)):
                slaac = a
                break
        if slaac:
            break
        time.sleep(2)
    res.check("ipv6_slaac_addr", slaac is not None,
              slaac or "no fd00:5c1: /64 addr (RA not processed?)")

    # RA-derived routes can lag by one advertisement interval; netlab
    # advertises every 10s, so wait comfortably past that.
    got_route = False
    deadline = time.time() + 35
    while time.time() < deadline:
        rc, out = guest.run("ip -6 route")
        if re.search(r"default via fe80::[0-9a-f:]+ dev eth0", out):
            got_route = True
            break
        time.sleep(3)
    res.check("ipv6_default_route", got_route, "default route from RA")

    if slaac:
        res.check("ipv6_host_ping_global", lab.ping(slaac, v6=True),
                  f"ping {slaac}")

    # Stateful DHCPv6: odhcp6c should be running and holding an address
    # from the dnsmasq IA_NA range (::100 - ::1ff, distinct from SLAAC).
    rc, out = guest.run("ps w | grep -v grep | grep odhcp6c")
    odhcp_running = "odhcp6c" in out
    res.check("odhcp6c_running", odhcp_running)

    dhcp6_addr = None
    deadline = time.time() + 30
    while time.time() < deadline:
        addrs = get_guest_addrs(guest)
        for a, _plen in addrs["v6_global"]:
            if in_dhcpv6_range(a):
                dhcp6_addr = a
        if dhcp6_addr:
            break
        time.sleep(2)
    res.check("dhcpv6_stateful_addr", dhcp6_addr is not None,
              dhcp6_addr or "no IA_NA address from DHCPv6 range")

    rc, out = guest.run("cat /etc/resolv.conf")
    res.check("ipv6_dns_in_resolv", "fd00:5c1::1" in out,
              "DNS from DHCPv6/RDNSS")
    return slaac


def test_dns_and_pref(guest, res, lab):
    # Explicit server query: the DHCP-provided DNS answers A records.
    # (Plain nslookup iterates every resolv.conf server including the
    # static public fallbacks, which have no route in the lab.)
    rc, out = guest.run("nslookup host.lab 192.168.100.1 2>&1", timeout=20)
    res.check("dns_a_lookup", out.count("192.168.100.1") >= 2,
              "" if out.count("192.168.100.1") >= 2 else out.strip()[:120])

    # libc resolver walks resolv.conf in order: first entry is the lab's
    # v6 server, so this passing proves the file ordering works.
    rc, out = guest.run("ping -4 -c 1 -W 2 host.lab 2>&1", timeout=10)
    res.check("dns_a_via_resolv", rc == 0,
              "A record resolves through resolv.conf order")

    rc, out = guest.run("ping -6 -c 1 -W 2 host.lab 2>&1", timeout=10)
    res.check("dns_aaaa_lookup", rc == 0 or "fd00:5c1::1" in out,
              "AAAA resolves and host reachable over v6")

    n_before = len(lab.http_echo.hits)
    rc, out = guest.run("curl -s http://host.lab:8080/", timeout=15)
    hit_fam = lab.http_echo.hits[-1][0] if len(lab.http_echo.hits) > n_before else None
    res.check("v6_preference", hit_fam == "v6",
              f"dual A/AAAA name connected over {hit_fam or 'nothing'}")


def test_dual_stack_listeners(guest, res):
    rc, out = guest.run("netstat -tln 2>/dev/null", timeout=15)
    res.check("http_listens_v6", ":::80" in out or "::80" in out.replace(" ", ""),
              "uhttpd should be dual-stack per IPv6-first policy")
    res.check("ssh_listens_v6", ":::22" in out)
    https = "0.0.0.0:443" in out or ":::443" in out
    res.check("https_listening", https)


def test_host_http(res, guest_v4, guest_v6):
    import urllib.request
    for fam, addr in (("v4", guest_v4), ("v6", f"[{guest_v6}]" if guest_v6 else None)):
        name = f"host_http_{fam}"
        if not addr:
            res.skip(name, "no address")
            continue
        try:
            req = urllib.request.urlopen(f"http://{addr}/", timeout=8)
            body = req.read(1024).decode(errors="replace")
            res.check(name, req.status == 200 and "<!DOCTYPE" in body)
        except Exception as e:
            res.fail(name, str(e)[:80])


def streamer_auth(guest):
    """SOAP creds the way the ONVIF server resolves them (conf.c
    load_streamer_auth): the installed streamer's own RTSP auth, first
    existing config wins; the pre-03e8595 onvif.json copy is only a
    legacy fallback. Returns (user, password, source)."""

    def nested(conf, dotted):
        node = conf
        for part in dotted.split("."):
            node = node.get(part) if isinstance(node, dict) else None
        return node if isinstance(node, str) and node else None

    def from_json(out, user_keys, pass_keys):
        try:
            conf = json.loads(out[out.index("{"):out.rindex("}") + 1])
        except ValueError:
            return None, None
        user = pw = None
        for k in user_keys:
            user = user or nested(conf, k)
        for k in pass_keys:
            pw = pw or nested(conf, k)
        return user, pw

    def flat_value(text, key):
        # Mirror the server's flat-file parser: first matching key wins,
        # an inline '#' comment counts only after whitespace, and one
        # level of quotes is removed.
        for line in text.splitlines():
            m = re.match(r"\s*" + re.escape(key) + r"\s*=\s*(.*)$", line)
            if not m:
                continue
            val = re.sub(r"\s+#.*$", "", m.group(1)).rstrip()
            if len(val) >= 2 and val[0] == val[-1] and val[0] in "\"'":
                val = val[1:-1]
            return val or None
        return None

    def cmd_value(cmd):
        rc, out = guest.run(cmd)
        for line in out.splitlines():
            line = line.strip()
            if line and "raptorctl" not in line:
                return line
        return None

    sources = [
        ("/etc/prudynt.json", "prudynt"),
        ("/etc/streamer.d/rtsp.json", "strero"),
        ("/etc/timps.conf", "timps"),
        ("/etc/raptor.conf", "raptor"),
        ("/etc/onvif.json", "onvif.json"),
    ]
    for path, kind in sources:
        rc, out = guest.run(f"[ -r {path} ] && echo CREDSRC || true")
        if "CREDSRC" not in out:
            continue
        if kind == "prudynt":
            rc, out = guest.run(f"cat {path}")
            user, pw = from_json(out, ["rtsp.username"], ["rtsp.password"])
        elif kind == "strero":
            rc, out = guest.run(f"cat {path}")
            user, pw = from_json(
                out, ["username", "auth.username", "rtsp.username"],
                ["password", "auth.password", "rtsp.password"])
        elif kind == "timps":
            rc, out = guest.run(f"cat {path}")
            user = flat_value(out, "rtsp.user")
            pw = flat_value(out, "rtsp.pass")
        elif kind == "raptor":
            user = cmd_value("raptorctl config get rtsp username")
            pw = cmd_value("raptorctl config get rtsp password")
        else:
            rc, out = guest.run(f"cat {path}")
            user, pw = from_json(out, ["server.username"],
                                 ["server.password"])
        # Like the server: the first existing config decides, even if it
        # holds no creds (the server then requires no auth either).
        return user, pw, kind
    return None, None, "none"


def test_onvif(guest, res, lab, guest_v4, report_dir):
    from onvif import OnvifDevice, xml_tag

    def dump(name, status, text):
        with open(os.path.join(report_dir, f"onvif-{name}.xml"), "w") as f:
            f.write(f"<!-- HTTP {status} -->\n{text}")

    ok = False
    deadline = time.time() + 60
    while time.time() < deadline:
        rc, out = guest.run("ps w | grep -v grep | grep wsd_simple_server")
        if "wsd_simple_server" in out:
            ok = True
            break
        time.sleep(3)
    res.check("onvif_wsd_running", ok)

    replies = lab.ws_discovery_probe()
    match = [r for r in replies if "NetworkVideoTransmitter" in r
             or "XAddrs" in r]
    xaddrs = xml_tag(match[0], "XAddrs") if match else None
    res.check("onvif_ws_discovery", bool(match),
              xaddrs or f"{len(replies)} multicast replies")

    user, password, cred_src = streamer_auth(guest)

    dev = OnvifDevice(guest_v4, user=user, password=password or "")

    status, text = dev.get_system_date_and_time()
    dump("datetime", status, text)
    year = xml_tag(text, "Year")
    res.check("onvif_datetime", status == 200 and year is not None,
              f"year={year}")

    status, text = dev.get_device_information()
    dump("device-info", status, text)
    mfr = xml_tag(text, "Manufacturer")
    fw = xml_tag(text, "FirmwareVersion")
    res.check("onvif_device_info", status == 200 and mfr is not None,
              f"{mfr} fw={fw} creds={cred_src}" if mfr
              else f"HTTP {status} (creds={cred_src}): {text[:110]}")

    status, text = dev.get_capabilities()
    dump("capabilities", status, text)
    media_xaddr = None
    m = re.search(r"<(?:[\w.-]+:)?Media>.*?<(?:[\w.-]+:)?XAddr>(.*?)<",
                  text, re.DOTALL)
    if m:
        media_xaddr = m.group(1).strip()
    res.check("onvif_capabilities", status == 200 and media_xaddr is not None,
              media_xaddr or f"HTTP {status}: {text[:120]}")

    if media_xaddr:
        dev.media_url = media_xaddr

    status, text = dev.get_profiles()
    dump("profiles", status, text)
    tokens = re.findall(r"<(?:[\w.-]+:)?Profiles[^>]*?token=\"([^\"]+)\"", text)
    res.check("onvif_media_profiles", status == 200 and len(tokens) > 0,
              f"{len(tokens)} profiles: {tokens[:4]}" if tokens
              else f"HTTP {status}: {text[:120]}")

    if tokens:
        status, text = dev.get_stream_uri(tokens[0])
        dump("stream-uri", status, text)
        uri = xml_tag(text, "Uri") or ""
        res.check("onvif_stream_uri",
                  status == 200 and
                  bool(re.match(r"rtsps?://[^/:]+(:\d+)?/", uri)),
                  uri or f"HTTP {status}")

        status, text = dev.get_snapshot_uri(tokens[0])
        dump("snapshot-uri", status, text)
        uri = xml_tag(text, "Uri") or ""
        res.check("onvif_snapshot_uri",
                  status == 200 and
                  bool(re.match(r"https?://[^/]+/", uri)),
                  uri or f"HTTP {status}")


def test_mdns(guest, res, lab, guest_v4):
    rc, hostname = guest.run("hostname")
    hostname = hostname.strip().split("\n")[-1].strip()
    if not hostname:
        res.fail("mdns_resolve_a", "could not read hostname")
        return

    # mdnsd re-probes (and goes silent for a few seconds) whenever an
    # address event fires, RA lifetime refreshes included. Real mDNS
    # clients retry; a dead responder still fails every attempt.
    def mq(name, rtype, tries=3):
        for i in range(tries):
            r = lab.mdns_query(name, rtype)
            if r:
                return r
            time.sleep(3)
        return []

    a = mq(f"{hostname}.local", "A")
    res.check("mdns_resolve_a", guest_v4 in a,
              f"{hostname}.local -> {a}")
    aaaa = mq(f"{hostname}.local", "AAAA")
    res.check("mdns_resolve_aaaa", len(aaaa) > 0,
              f"{hostname}.local AAAA -> {aaaa}" if aaaa
              else "no AAAA (mdnsd v4-only?)")

    # DNS-SD: this mdnsd doesn't answer the _services._dns-sd._udp
    # meta-enumeration, so browse the concrete types S50mdnsd generates
    found = {}
    for stype in ("_http._tcp", "_thingino._tcp", "_rtsp._tcp",
                  "_rtsps._tcp"):
        insts = mq(f"{stype}.local", "PTR", tries=2)
        if insts:
            found[stype] = insts[0]
    res.check("mdns_service_browse",
              "_http._tcp" in found and "_thingino._tcp" in found,
              f"advertised: {sorted(found)}")
    res.check("mdns_rtsp_advertised",
              "_rtsp._tcp" in found or "_rtsps._tcp" in found,
              "streamer RTSP service in DNS-SD")

    instances = lab.mdns_query("_http._tcp.local", "PTR", timeout=4)
    if instances:
        srv = lab.mdns_query(instances[0], "SRV", timeout=4)
        res.check("mdns_http_srv",
                  any(s.startswith("80 ") and hostname in s for s in srv),
                  f"{instances[0]} SRV -> {srv}")
    else:
        res.fail("mdns_http_srv", "no _http._tcp instance answered")


def test_ntp(guest, res, lab):
    before = lab.sntp.requests
    rc, out = guest.run("ntpd -n -q -p 192.168.100.1 2>&1", timeout=30)
    served = lab.sntp.requests > before
    res.check("ntp_query", served,
              f"{lab.sntp.requests - before} SNTP requests answered")
    rc, out = guest.run("date -u +%Y")
    year = out.strip().split("\n")[-1].strip()
    res.check("clock_sane", year.isdigit() and int(year) >= 2025,
              f"year={year}")


def test_syslog_remote(guest, res, lab):
    """Point busybox syslogd at the host sink and verify delivery."""
    guest.run("killall syslogd 2>/dev/null; sleep 1; "
              "syslogd -R 192.168.100.1", timeout=10)
    time.sleep(2)
    marker = f"qemu-test-syslog-{int(time.time())}"
    guest.run(f"logger {marker}")
    got = False
    deadline = time.time() + 10
    while time.time() < deadline:
        if any(marker in msg for _, msg in lab.syslog.messages):
            got = True
            break
        time.sleep(1)
    res.check("syslog_remote_delivery", got,
              f"{len(lab.syslog.messages)} messages received")
    guest.run("killall syslogd 2>/dev/null; /etc/init.d/S01syslogd start "
              ">/dev/null 2>&1", timeout=10)


def test_link_flap(guest, res, qmp, lab, guest_v4):
    """Drop and restore the link via QMP. The GMAC model mirrors the
    backend link state into the PHY's BMSR, and the guest drivers poll
    the PHY, so carrier must follow within a few poll intervals."""
    qmp.set_link("n0", False)
    time.sleep(3)
    res.check("link_down_datapath", not lab.ping(guest_v4),
              "host ping must fail while link is down")
    # phylib polls the PHY every second of guest time, which can lag
    # wall time badly on loaded runners: poll instead of one shot.
    carrier_down = False
    deadline = time.time() + 20
    while time.time() < deadline:
        rc, out = guest.run("cat /sys/class/net/eth0/carrier 2>&1",
                            via="serial")
        if out.strip().endswith("0"):
            carrier_down = True
            break
        time.sleep(2)
    res.check("link_down_carrier", carrier_down,
              "carrier must drop with the link")

    qmp.set_link("n0", True)
    ok = False
    deadline = time.time() + 60
    while time.time() < deadline:
        if lab.ping(guest_v4):
            ok = True
            break
        time.sleep(2)
    res.check("link_up_datapath", ok, "host ping works again")

    rc, out = guest.run("ip -4 addr show eth0", via="serial")
    res.check("link_flap_addr_kept", "192.168.100." in out)


def warm_reset_timer_wedge(report_dir):
    """QEMU fork bug: after a system reset the TCU/OST model can fire
    pathological timer interrupts (hrtimer latencies in the tens of ms,
    RT throttling), leaving the guest crawling. Detect the signature."""
    try:
        with open(os.path.join(report_dir, "serial.log"), "rb") as f:
            f.seek(max(0, os.fstat(f.fileno()).st_size - 16384))
            tail = f.read().decode(errors="replace")
        if ("RT throttling activated" in tail
                or "hrtimer: interrupt took" in tail):
            return True
        # Second presentation: the rebooted kernel comes up at normal
        # speed, then the guest dies at the userspace handoff (timer
        # interrupts stop entirely, nothing ever schedules).
        last = [l for l in tail.strip().split("\n") if l.strip()]
        return bool(last and "Freeing unused kernel memory" in last[-1])
    except OSError:
        return False


def test_persist_reboot(ser, guest, res, report_dir, timeout=240):
    """Overlay persistence: write markers, reboot, verify."""
    print("\n── Persistence reboot ──")
    marker = f"marker-{int(time.time())}"
    guest.run(f"touch /etc/qemu-test-marker && "
              f"jct /etc/thingino.json set qemutest {marker}",
              via="serial", timeout=15)
    ser.read()                 # drop the pre-reboot prompt still buffered
    ser.write("reboot\n")
    time.sleep(5)
    # expect_reboot: do not accept a prompt until the machine has actually
    # reset, so we assert persistence against the rebooted system and not
    # the dying pre-reboot shell.
    if not ser.login(timeout, expect_reboot=True):
        if warm_reset_timer_wedge(report_dir):
            res.xfail("persist_reboot_complete", False,
                      "QEMU warm-reset timer wedge (fork bug, "
                      "guest crawls after system reset)")
            res.skip("persist_file", "reboot did not complete")
            res.skip("persist_config", "reboot did not complete")
        else:
            res.fail("persist_reboot_complete",
                     "no login prompt after reboot")
        return
    res.ok("persist_reboot_complete")
    guest.ssh_ok = False

    # Positive sentinel: a bare "not absent" check reads as success against
    # a U-Boot "syntax error" too, so confirm the file is really there.
    rc, out = guest.run("[ -f /etc/qemu-test-marker ] && echo MARKER_OK",
                        via="serial")
    res.check("persist_file", "MARKER_OK" in out)
    rc, out = guest.run("jct /etc/thingino.json get qemutest 2>&1",
                        via="serial")
    res.check("persist_config", marker in out)
    rc, out = guest.run("rm -f /etc/qemu-test-marker; "
                        "jct /etc/thingino.json del qemutest 2>&1",
                        via="serial")


def collect_artifacts(guest, report_dir):
    """Best-effort dump of guest logs into the report dir."""
    for name, cmd in (("dmesg.txt", "dmesg"),
                      ("logread.txt", "logread 2>/dev/null | tail -n 500"),
                      ("ps.txt", "ps w"),
                      ("netstat.txt", "netstat -tuln 2>/dev/null"),
                      ("ipaddr.txt", "ip addr; ip route; ip -6 route")):
        try:
            rc, out = guest.run(cmd, timeout=25)
            with open(os.path.join(report_dir, name), "w") as f:
                f.write(out)
        except Exception:
            pass


def run_playwright(res, report_dir, mode, urls, timeout=120,
                  check_name="playwright_tests"):
    print("\n── Playwright ──")
    script_dir = os.path.dirname(os.path.abspath(__file__))
    env = os.environ.copy()
    env["REPORT_DIR"] = report_dir
    env.update(urls)
    if os.geteuid() == 0:
        env["CHROMIUM_NO_SANDBOX"] = "1"
        # browsers live in the invoking user's cache, not root's
        sudo_user = os.environ.get("SUDO_USER")
        if sudo_user and "PLAYWRIGHT_BROWSERS_PATH" not in env:
            import pwd
            home = pwd.getpwnam(sudo_user).pw_dir
            env["PLAYWRIGHT_BROWSERS_PATH"] = os.path.join(
                home, ".cache", "ms-playwright")
    npx = os.environ.get("NPX_BIN") or "npx"
    pw = subprocess.run(
        [npx, "playwright", "test",
         "--config", os.path.join(script_dir, "playwright.config.js")],
        cwd=script_dir, env=env, capture_output=True, text=True,
        timeout=timeout)
    print(pw.stdout)
    if pw.stderr:
        print(pw.stderr[:500])
    res.check(check_name, pw.returncode == 0, f"exit {pw.returncode}")
    return pw.returncode == 0


# ── Main ─────────────────────────────────────────────────────

def main():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--image", required=True, help="Path to thingino .bin image")
    p.add_argument("--soc", required=True, help="SoC variant (t31x, t10n, ...)")
    p.add_argument("--mode", required=True, choices=["wifi", "eth", "ethwifi"],
                   help="Device modality to test")
    p.add_argument("--net", default="slirp", choices=["slirp", "tap"],
                   help="Network backend (tap enables the full network lab)")
    p.add_argument("--qemu", default=None, help="Path to qemu-system-mipsel")
    p.add_argument("--timeout", type=int, default=240,
                   help="Boot timeout in seconds")
    p.add_argument("--host-tests", action="store_true",
                   help="Also run host-side HTTP tests (slirp mode)")
    p.add_argument("--playwright", action="store_true",
                   help="Run Playwright browser tests")
    p.add_argument("--reboot-test", action="store_true",
                   help="Run reboot persistence / STA connection tests")
    p.add_argument("--report-dir", default=None,
                   help="Report output dir (default: output/<branch>/qemu-test-reports/)")
    p.add_argument("--profile", default=None,
                   help="Profile name for reporting (default qemu_<soc>)")
    p.add_argument("--only", default=None,
                   help="Comma list of optional suites to run (eth modes): "
                        "ipv6,dns,health,webui,onvif,services,playwright,"
                        "linkflap,persist")
    args = p.parse_args()

    if args.soc not in SOC_MACHINES:
        sys.exit(f"Unknown SoC: {args.soc}")
    if args.net == "tap" and os.geteuid() != 0:
        sys.exit("tap mode requires root (use run.sh, it handles sudo)")

    machine, ram = SOC_MACHINES[args.soc]
    qemu = args.qemu or find_qemu()
    image = os.path.abspath(args.image)
    profile = args.profile or f"qemu_{args.soc}"

    repo_root = os.path.dirname(os.path.dirname(os.path.dirname(
        os.path.abspath(__file__))))
    if not args.report_dir:
        branch = "master"
        try:
            branch = subprocess.check_output(
                ["git", "-C", repo_root, "rev-parse", "--abbrev-ref", "HEAD"],
                text=True, stderr=subprocess.DEVNULL).strip()
        except Exception:
            pass
        args.report_dir = os.path.join(
            repo_root, "output", branch, "qemu-test-reports", profile)

    if not os.path.isfile(image):
        sys.exit(f"Image not found: {image}")

    report_dir = args.report_dir
    os.makedirs(report_dir, exist_ok=True)

    commit = ""
    try:
        commit = subprocess.check_output(
            ["git", "-C", repo_root, "rev-parse", "HEAD"],
            text=True, stderr=subprocess.DEVNULL).strip()
    except Exception:
        pass

    meta = {
        "profile": profile, "soc": args.soc, "mode": args.mode,
        "net": args.net, "machine": machine, "ram_mb": ram,
        "image": os.path.basename(image), "qemu": qemu,
        "commit": commit,
    }

    # Work on a copy so writes don't taint the original
    tmp_image = f"/tmp/qemu-test-{os.getpid()}.bin"
    shutil.copy2(image, tmp_image)

    print(f"Testing {profile} ({args.mode}, {args.net}) "
          f"with {os.path.basename(image)}")
    print(f"QEMU: {qemu}")
    print(f"Machine: {machine}, RAM: {ram}M")
    print()

    lab = None
    if args.net == "tap":
        from netlab import NetLab
        lab = NetLab(report_dir)
        lab.up()

    t_start = time.time()
    proc, pty, qmp_path = start_qemu(qemu, tmp_image, machine, ram,
                                     args.net, report_dir,
                                     tap_if=lab.tap if lab else "qtap0")
    ser = QemuSerial(proc, pty,
                     log_path=os.path.join(report_dir, "serial.log"))
    guest = Guest(ser)
    res = TestResult()
    qmp = None

    def cleanup(sig=None, frame=None):
        try:
            ser.close()
        except Exception:
            pass
        if qmp:
            qmp.close()
        proc.terminate()
        proc.wait()
        try:
            os.unlink(tmp_image)
        except Exception:
            pass
        if lab:
            lab.down()
        if sig:
            sys.exit(128 + sig)

    signal.signal(signal.SIGINT, cleanup)
    signal.signal(signal.SIGTERM, cleanup)

    try:
        print("── Boot ──")
        if not ser.login(args.timeout):
            print("  FAIL  boot (no login prompt)")
            # Freeze evidence before teardown: two register snapshots
            # 5 s apart tell a hard CPU freeze (PCs identical) from a
            # slow or wedged-but-running guest.
            stamp = int(time.time())
            try:
                qmp = Qmp(qmp_path)
                for tag in ("t0", "t5"):
                    regs = qmp.cmd("human-monitor-command",
                                   **{"command-line": "info registers -a"})
                    with open(os.path.join(report_dir,
                                           f"bootfail-{stamp}-regs-{tag}.txt"),
                              "w") as f:
                        f.write(str(regs))
                    if tag == "t0":
                        time.sleep(5)
                qmp.close()
            except Exception as e:
                print(f"  (bootfail register dump failed: {e})")
            try:
                shutil.copy2(os.path.join(report_dir, "serial.log"),
                             os.path.join(report_dir,
                                          f"bootfail-{stamp}-serial.log"))
            except OSError:
                pass
            cleanup()
            sys.exit(2)
        boot_s = time.time() - t_start
        meta["boot_seconds"] = round(boot_s, 1)
        res.ok("boot", f"{boot_s:.0f}s to login")

        try:
            qmp = Qmp(qmp_path)
        except RuntimeError as e:
            print(f"  (QMP unavailable: {e})")

        test_boot(guest, res, meta)
        test_services(guest, res, args.mode)

        if args.mode == "wifi":
            print("\n── WiFi ──")
            test_wifi_modules(guest, res)
            test_wifi_portal(guest, res)
            print("\n── Health ──")
            test_health(guest, res)

            if args.host_tests:
                print("\n── Bridge setup ──")
                test_wifi_bridge_setup(guest, res)
                time.sleep(2)
                setup_ssh(guest, ser, res, report_dir,
                          "127.0.0.1", SSH_FWD_PORT)
                print("\n── Host access ──")
                test_host_portal_access(res)

            if args.playwright and args.host_tests:
                ok = run_playwright(res, report_dir, args.mode, {
                    "PORTAL_URL": f"http://localhost:{PORTAL_PORT}",
                    "WEBUI_URL": f"http://localhost:{WEBUI_PORT + 1}",
                    "WEBUI_PORT": str(WEBUI_PORT + 1),
                    "SKIP_WEBUI": "1",
                })
                if ok and args.reboot_test:
                    test_provision_reboot_sta(ser, guest, res, report_dir,
                                              qmp=qmp,
                                              timeout=max(args.timeout, 240))

        else:  # eth / ethwifi
            print("\n── Ethernet ──")
            test_ethernet(guest, res, lab)

            if args.mode == "ethwifi":
                print("\n── Ethernet + WiFi behavior ──")
                test_ethwifi_behavior(guest, res)

            def want(suite):
                return not args.only or suite in args.only.split(",")

            guest_v4 = guest_v6 = None
            if lab:
                print("\n── IPv4 DHCP ──")
                guest_v4 = test_ipv4_dhcp(guest, res, lab)
                if guest_v4:
                    setup_ssh(guest, ser, res, report_dir, guest_v4)
                if want("ipv6"):
                    print("\n── IPv6 ──")
                    guest_v6 = test_ipv6(guest, res, lab)
                if want("dns"):
                    print("\n── DNS / dual-stack ──")
                    test_dns_and_pref(guest, res, lab)
                    test_dual_stack_listeners(guest, res)

            if want("health"):
                print("\n── Health ──")
                test_health(guest, res)

            if want("webui"):
                print("\n── Web UI ──")
                test_webui(guest, res)
                if lab and guest_v4:
                    test_host_http(res, guest_v4, guest_v6)

            if lab and guest_v4:
                if want("onvif"):
                    print("\n── ONVIF ──")
                    test_onvif(guest, res, lab, guest_v4, report_dir)
                if want("services"):
                    print("\n── mDNS / NTP / syslog ──")
                    test_mdns(guest, res, lab, guest_v4)
                    test_ntp(guest, res, lab)
                    test_syslog_remote(guest, res, lab)

            if args.playwright and lab and guest_v4 and want("playwright"):
                run_playwright(res, report_dir, args.mode, {
                    "PORTAL_URL": f"http://{guest_v4}",
                    "WEBUI_URL": f"http://{guest_v4}",
                    "WEBUI_PORT": "80",
                    "SKIP_WEBUI": "0",
                    "SKIP_PORTAL": "1",
                    "SKIP_PROVISION": "1",
                })
            elif args.host_tests and not lab:
                print("\n── Host access ──")
                test_host_webui_access(res)

            if lab and qmp and guest_v4 and want("linkflap"):
                print("\n── Link flap ──")
                test_link_flap(guest, res, qmp, lab, guest_v4)

            if args.reboot_test and want("persist"):
                test_persist_reboot(ser, guest, res, report_dir,
                                    timeout=max(args.timeout, 240))

        print("\n── Artifacts ──")
        collect_artifacts(guest, report_dir)

    finally:
        serial_json = os.path.join(report_dir, "serial-results.json")
        res.save_json(serial_json)
        with open(os.path.join(report_dir, "meta.json"), "w") as f:
            json.dump(meta, f, indent=2)

        from report import generate_report
        generate_report(res.results, report_dir,
                        profile=profile, mode=args.mode, meta=meta)
        cleanup()

    success = res.summary()
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
