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
import shutil
import signal
import subprocess
import sys
import time
from .config import PROFILES_DIR, REPO_ROOT, SOC_MACHINES
from .context import Ctx
from .guest import Guest
from .launch import find_qemu, start_qemu
from .plan import OPTIONAL_SUITES, run_suites
from .profile import host_qemu, load as load_profile, newest_image
from .netlab import enter_netns
from .qmp import Qmp
from .results import TestResult, load_expected
from .serial import QemuSerial


def collect_artifacts(guest, report_dir):
    """Best-effort dump of guest logs into the report dir."""
    if guest.ser.state != "shell":
        print(f"  (artifacts skipped: guest not at shell: {guest.ser.state})")
        return
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


def main():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--profile", default=None,
                   help="Test profile (configs/cameras-testing/<name>); its "
                        "qemu-test.json supplies SoC, capabilities, backend "
                        "and the default flags, and the newest built image "
                        "is used unless --image is given")
    p.add_argument("--image", default=None, help="Path to thingino .bin image")
    p.add_argument("--soc", default=None, help="SoC variant (t31x, t10n, ...)")
    p.add_argument("--mode", default=None, choices=["wifi", "eth", "ethwifi"],
                   help="Device modality, when not running a profile")
    p.add_argument("--net", default=None, choices=["slirp", "tap"],
                   help="Network backend (tap enables the full network lab)")
    p.add_argument("--qemu", default=None, help="Path to qemu-system-mipsel")
    p.add_argument("--timeout", type=int, default=240,
                   help="Boot timeout in seconds")
    p.add_argument("--host-tests", action="store_true", default=None,
                   help="Also run host-side HTTP tests (slirp mode)")
    p.add_argument("--playwright", action="store_true", default=None,
                   help="Run Playwright browser tests")
    p.add_argument("--reboot-test", action="store_true", default=None,
                   help="Run reboot persistence / STA connection tests")
    p.add_argument("--report-dir", default=None,
                   help="Report output dir (default: output/<branch>/qemu-test-reports/)")
    p.add_argument("--only", default=None,
                   help="Comma list of optional suites to run: "
                        + ",".join(OPTIONAL_SUITES))
    p.add_argument("--update-expected", action="store_true",
                   help="Record this run's check list as the profile's "
                        "expected list instead of enforcing it")
    args = p.parse_args()

    # A profile supplies everything a run needs; explicit flags override.
    # Without one, --image/--soc/--mode describe the run by hand.
    if args.profile and not (args.image and args.soc and args.mode):
        try:
            prof = load_profile(args.profile)
        except FileNotFoundError:
            sys.exit(f"No qemu-test.json for {args.profile} under "
                     f"{os.path.relpath(PROFILES_DIR, REPO_ROOT)}")
        args.soc = args.soc or prof.soc
        args.mode = args.mode or prof.mode
        args.net = args.net or prof.net
        caps = prof.caps
        for flag, value in prof.defaults().items():
            if getattr(args, flag) is None:
                setattr(args, flag, value)
        if not args.image:
            args.image = newest_image(args.profile)
            if not args.image:
                sys.exit(f"No built image found for {args.profile} "
                         f"(looked in output/**/{args.profile}-*/images/)\n"
                         f"Build it with: make GROUP=testing "
                         f"CAMERA={args.profile}")
        if not args.qemu and not os.environ.get("QEMU_BIN"):
            args.qemu = host_qemu(args.image)
    else:
        missing = [f for f in ("image", "soc", "mode") if not getattr(args, f)]
        if missing:
            sys.exit("give --profile, or all of --image/--soc/--mode "
                     "(missing: " + ", ".join("--" + m for m in missing) + ")")
        caps = {"wired"} if args.mode in ("eth", "ethwifi") else set()
        if args.mode in ("wifi", "ethwifi"):
            caps.add("wifi")
    args.net = args.net or "slirp"
    for flag in ("host_tests", "playwright", "reboot_test"):
        if getattr(args, flag) is None:
            setattr(args, flag, False)
    args.caps = sorted(caps)

    if args.soc not in SOC_MACHINES:
        sys.exit(f"Unknown SoC: {args.soc}")
    if args.net == "tap" and os.geteuid() != 0:
        # The lab needs root. Runner sudo policies ignore -E, so carry the
        # inputs as explicit assignments; npx must stay findable across
        # sudo's secure_path.
        npx = os.environ.get("NPX_BIN") or shutil.which("npx") or ""
        carry = {"QEMU_BIN": os.environ.get("QEMU_BIN", args.qemu or ""),
                 "NPX_BIN": npx,
                 "PLAYWRIGHT_BROWSERS_PATH":
                     os.environ.get("PLAYWRIGHT_BROWSERS_PATH", ""),
                 "SERIAL_PACE_MS": os.environ.get("SERIAL_PACE_MS", "")}
        # Hand the resolved image and qemu to the re-exec'd copies so they
        # do not resolve the profile again (last occurrence wins in argparse).
        resolved = ["--image", args.image] + (["--qemu", args.qemu] if args.qemu else [])
        os.execvp("sudo", ["sudo", "-E", *(f"{k}={v}" for k, v in carry.items()),
                           sys.executable, *sys.argv, *resolved])
    if args.net == "tap":
        enter_netns()          # re-execs once; returns only when inside

    machine, ram = SOC_MACHINES[args.soc]
    qemu = args.qemu or find_qemu()
    image = os.path.abspath(args.image)
    profile = args.profile or f"qemu_{args.soc}"

    repo_root = REPO_ROOT
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
        from .netlab import NetLab
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
    ctx = Ctx(guest, ser, res, args, report_dir, meta)
    ctx.lab = lab
    only = [s.strip() for s in args.only.split(",")] if args.only else None

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

        ctx.qmp = qmp
        run_suites(ctx, only)

        print("\n── Artifacts ──")
        collect_artifacts(guest, report_dir)

    finally:
        serial_json = os.path.join(report_dir, "serial-results.json")
        res.save_json(serial_json)
        with open(os.path.join(report_dir, "meta.json"), "w") as f:
            json.dump(meta, f, indent=2)

        from .report import generate_report
        generate_report(res.results, report_dir,
                        profile=profile, mode=args.mode, meta=meta)
        cleanup()

    success = res.summary()

    # The ordered check list is the contract a profile makes with its
    # readers (reports, CI diffs). It lives beside the profile and any
    # deviation fails the run, so a check cannot silently disappear.
    expected_file = os.path.join(PROFILES_DIR, profile, "expected-checks.txt")
    shown = os.path.relpath(expected_file, REPO_ROOT)
    if args.update_expected:
        with open(expected_file, "w") as f:
            f.write("\n".join(res.names()) + "\n")
        print(f"Expected check list written to {shown}"
              + ("" if success else " (from a run with failures)"))
    elif args.only:
        pass                        # a partial run by design
    elif os.path.exists(expected_file):
        diff = res.diff_expected(load_expected(expected_file))
        if diff:
            print(f"\nEXPECTED CHECK LIST MISMATCH ({shown})")
            for line in diff:
                print(line)
            print("(rerun with --update-expected if the change is intended)")
            success = False
        else:
            print(f"Check list matches {shown}")
    else:
        print(f"(no expected check list at {shown}; "
              "run with --update-expected to record one)")
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
