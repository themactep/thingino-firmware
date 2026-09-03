"""Locating and starting QEMU, plus boot-failure diagnostics."""

import os
import re
import shutil
import subprocess
import sys
import time
from .config import PORTAL_PORT, SSH_FWD_PORT, WEBUI_PORT


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
