"""Suites that apply to every profile."""

import os
import re
import subprocess


def test_boot(ctx):
    guest, res, meta = ctx.guest, ctx.res, ctx.meta
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


def test_services(ctx):
    guest, res, mode = ctx.guest, ctx.res, ctx.mode
    rc, out = guest.run("ps w")
    res.check("dropbear_running", "dropbear" in out)
    res.check("syslogd_running", "syslogd" in out)
    if mode == "wifi":
        res.check("wpa_supplicant_running", "wpa_supplicant" in out)


def test_health(ctx):
    """Kernel and system health gates."""
    guest, res = ctx.guest, ctx.res
    rc, out = guest.run("dmesg", timeout=30)
    bad = re.findall(r"(Oops|BUG:|Kernel panic|Unable to handle)", out)
    # "Call Trace" is fatal unless it is the ingenic-sdk sensor probe
    # diagnostic dump (no sensor on QEMU's auto-NACK I2C, expected).
    lines = out.split("\n")
    benign = 0
    for i, line in enumerate(lines):
        if "Call Trace" in line:
            preceding = "\n".join(lines[max(0, i - 10):i])
            if re.search(r"is not an? \w+ chip", preceding):
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


def setup_ssh(ctx, addr, port=22):
    """Install an ephemeral pubkey via serial, then switch to SSH."""
    guest, ser, res, report_dir = ctx.guest, ctx.ser, ctx.res, ctx.report_dir
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
