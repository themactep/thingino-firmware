"""Development sessions: a thingino image under the Ingenic QEMU fork,
running in the background and driven one command at a time.

  qemu-dev images                          built images and their SoCs
  qemu-dev up CAMERA|IMAGE [--uboot]       boot one (replaces its session)
  qemu-dev sh [NAME] -- CMD...             run CMD, exit with its status
  qemu-dev put [NAME] LOCAL REMOTE         copy a file onto the camera
  qemu-dev get [NAME] REMOTE LOCAL         copy a file off it
  qemu-dev log [NAME] [--boot] [-n N] [-f] the console output
  qemu-dev reboot [NAME] [--uboot|--hard]  reboot, wait for the shell
  qemu-dev uboot [NAME] -- CMD...          a U-Boot command (after --uboot)
  qemu-dev wait [NAME]                     the shell, after --no-wait
  qemu-dev send [NAME] -- TEXT             type at the console (--expect RE)
  qemu-dev monitor [NAME] -- COMMAND       a QEMU monitor command
  qemu-dev gpio [NAME] [PB14[=0] ...]      read pins, or drive inputs
  qemu-dev gpio [NAME] --log|--serve       pin changes (--watch, --vcd FILE)
  qemu-dev adc [NAME] [0[=150] ...]        read or set ADC channels
  qemu-dev console [NAME]                  attach a terminal; Ctrl-] detaches
  qemu-dev ls | info [NAME] | down [NAME|--all]

Each session is one QEMU with its own copy of the flash, so the image
under output/ is never written. NAME defaults to the only session.
Commands go over the serial console on every image. With a wired
interface, file copies take SSH instead, and the camera's SSH, HTTP and
HTTPS are forwarded to 127.0.0.1. More in docs/dev/qemu.md.
"""

import argparse
import base64
import codecs
import contextlib
import fcntl
import glob
import hashlib
import json
import os
import platform
import re
import secrets
import select
import shlex
import shutil
import signal
import socket
import subprocess
import sys
import tarfile
import tempfile
import time

from .config import REPO_ROOT, SCRIPT_DIR, SOC_MACHINES, SSH_OPTS
from .fdt import msc0_card_detect
from .qmp import Qmp
from .serial import QemuSerial

PROG = sys.argv[0] or "qemu-dev"

# SPI NAND images run on a 128 MiB GigaDevice GD5F1GQ5UE: the SPL, U-Boot
# and Linux of thingino and vendor NAND builds all know it
NAND_ID = 0xc851
NAND_SIZE = 128 << 20

# The soc-variant names the pinned fork knows; any other model boots as
# its machine's default variant.
FORK_VARIANTS = set("""
    t10 t10l t20n t20x t20l t21n t21l t21z t23n t23x t23dl t23zn
    t30n t30x t30l t30a t30z t31n t31x t31l t31a t31zl t31zx t31al t31zc
    t31lc t32nq t32lq t32xq t32zn t33n t40n t40nn t40xp t40a t41nq t41lq
    t41zx a1n a1l a1x a1a a1nt t10n t10a c100 t33zl t33zn t41xq t32prozl
    t32prozn t32prozx t32provl t32provn t32provx t32provnp t32proa cw080sn
    cw080snp""".split())

# An Ingenic model is its family plus letters: t31x, t21zn, a1nt, c100,
# cw080sn
SOC = re.compile(r"(t[1-4]\d|a1|c100|cw080)[a-z]*")
GUEST_PORTS = {"ssh": 22, "http": 80, "https": 443}
# The fork's model of each Wi-Fi package, by package or camera-name suffix
WIFI_CHIPS = {
    "aic8800_usb_8800": "aic8800", "aic8800d": "aic8800",
    "aic8800_usb_8800d80": "aic8800d80", "aic8800u": "aic8800d80",
    "aic8800_sdio_8800d80": "aic8800d80-sdio",
    "aic8800d40": "aic8800d80-sdio",
    "aic8800_usb_8800dc": "aic8800dc", "aic8800dc": "aic8800dc",
    "aic8800dw": "aic8800dw",
    "atbm6031": "atbm6031", "atbm6031x": "atbm6031",
    "atbm6062s": "atbm6062s", "atbm6162s": "atbm6162s",
    "atbm6012b": "atbm6012b", "atbm6012bx": "atbm6012bx",
    "atbm6032": "atbm6032", "atbm6132u": "atbm6132u",
    "atbm6132bu": "atbm6132u", "atbm6062": "atbm6062u",
    "atbm6062u": "atbm6062u", "atbm6062cu": "atbm6062cu",
    "atbm6132cu": "atbm6132cu", "atbm6132cu_6162": "atbm6132cu-6162",
    "rtl8189fs": "rtl8189fs", "rtl8189ftv": "rtl8189fs",
    "rtl8189es": "rtl8189es", "rtl8189etv": "rtl8189es",
    "rtl8192fs": "rtl8192fs",
    "rtl8188fu": "rtl8188fu", "rtl8188ftv": "rtl8188fu",
    "rtl8188eus": "rtl8188eu", "rtl8188eu": "rtl8188eu",
    "rtl8733bu": "rtl8733bu", "rtl8731bu": "rtl8733bu",
    "rtl8131bu": "rtl8733bu", "rtl8731": "rtl8733bu",
    "mt7601u": "mt7601u", "mt7601": "mt7601u", "mt7601sta": "mt7601u",
    "wq9001": "wq9001",
    "hi3881": "hi3881",
    "txw901u": "txw901u",
    "ws73v100": "ws73v100",
    "swt6621s": "swt6621s",
    "syn4343": "bcm43438",
    "ssv6155": "ssv6155p", "ssv6155p": "ssv6155p",
    "ssv6x5x_sv6155p": "ssv6155p",
    "ssv6256p": "ssv6155p", "ssv6x5x_sv6256p": "ssv6155p",
    "ssv6355": "ssv6355", "ssv6x5x_sv6355": "ssv6355",
    "ssv6158": "ssv6158",
}
# SDIO Wi-Fi sits on MSC1; the rest is USB, on the OTG port
SDIO_WIFI = {"aic8800d80-sdio", "atbm6031", "atbm6062s", "atbm6162s",
             "rtl8189fs", "rtl8189es", "rtl8192fs", "bcm43438", "bcm43436",
             "hi3881", "ssv6158"}
# thingino's setup portal network (S38wpa_supplicant). --portal's phone is
# the user netdev's host address on it, and takes the MAC that netdev sends
# from: 52:55, then the address.
PORTAL_NET = "172.16.0"
PORTAL_IP = PORTAL_NET + ".1"
PORTAL_PHONE = PORTAL_NET + ".250"
PORTAL_PSK = "thingino"
BANNER = re.compile(r"U-Boot SPL|Starting kernel|Restarting system")
ANSI = re.compile(r"\x1b(?:\[[0-9;?]*[A-Za-z]|[78])")
PROMPT = re.compile(r"root@[\w.-]+ \S*# ")
UBOOT_PROMPT = re.compile(r"(?:^|\n)([\w.-]+# |=> )$")
RESET = r"Restarting system|U-Boot SPL 20"
REBOOTED = -1
# The line editor's buffer is 1 KB; longer commands go over as a script
MAX_LINE = 900


ESCAPES = {"n": "\n", "r": "\r", "t": "\t", "e": "\x1b", "\\": "\\"}


def die(msg, code=1):
    print(f"{PROG}: {msg}", file=sys.stderr)
    sys.exit(code)


def clean(text):
    return ANSI.sub("", text).replace("\r\n", "\n").replace("\r", "")


def unescape(text):
    """\\n, \\r, \\t, \\e, \\xHH and \\\\, as typed on a command line."""
    return re.sub(r"\\(x[0-9a-fA-F]{2}|[nrte\\])",
                  lambda m: (chr(int(m.group(1)[1:], 16))
                             if m.group(1)[0] == "x" else ESCAPES[m.group(1)]),
                  text)


def state_root():
    """Where sessions live. Unix socket paths stop at 108 bytes, so this
    stays short."""
    if os.environ.get("QEMU_DEV_DIR"):
        return os.environ["QEMU_DEV_DIR"]
    run = os.environ.get("XDG_RUNTIME_DIR")
    if run and os.path.isdir(run):
        return os.path.join(run, "thingino-qemu-dev")
    return os.path.join(tempfile.gettempdir(),
                        f"thingino-qemu-dev-{os.getuid()}")


def built_images(camera="*"):
    """Built images, newest first. THINGINO_OUTPUT_ROOT_DIR and
    THINGINO_OUTPUT_DIR move the output tree, as they do for make."""
    pats = []
    if os.environ.get("THINGINO_OUTPUT_DIR"):
        pats.append(os.path.join(os.environ["THINGINO_OUTPUT_DIR"],
                                 "images", f"thingino-{camera}.bin"))
    root = (os.environ.get("THINGINO_OUTPUT_ROOT_DIR")
            or os.path.join(REPO_ROOT, "output"))
    pats.append(os.path.join(root, "*", "*", "images",
                             f"thingino-{camera}.bin"))
    hits = {p for pat in pats for p in glob.glob(pat)
            if not p.endswith("-update.bin")}
    return sorted(hits, key=os.path.getmtime, reverse=True)


def read_config(image):
    """The .config of the build that made the image, if it is in one."""
    cfg = {}
    path = os.path.join(os.path.dirname(os.path.dirname(image)), ".config")
    try:
        with open(path) as f:
            for line in f:
                m = re.match(r'(BR2_\w+)="?([^"\n]*)"?$', line)
                if m:
                    cfg[m.group(1)] = m.group(2)
    except OSError:
        pass
    return cfg


def resolve_image(target):
    if os.path.isfile(target):
        return os.path.abspath(target)
    hits = built_images(target)
    if hits:
        return hits[0]
    testing = os.path.isdir(os.path.join(REPO_ROOT, "configs",
                                         "cameras-testing", target))
    die(f"no image for {target}: build it with `make "
        f"{'GROUP=testing ' if testing else ''}CAMERA={target} fast`, "
        f"or give the path to a .bin")


def resolve_soc(image, cfg, soc):
    """(model, family): --soc, else the build's .config, else the SoC in
    the camera name (release images are named after the camera). Names
    run brand_model_soc_sensor_wifi and a model can look like a SoC
    (tapo_c100, wansview_a1), so the last match is the SoC."""
    model = soc or cfg.get("BR2_INGENIC_SOC_MODEL")
    if not model:
        words = re.split(r"[_.+-]", os.path.basename(image).lower())
        model = ([w for w in words if SOC.fullmatch(w)] or [None])[-1]
    m = SOC.fullmatch((model or "").lower())
    if not m:
        die("cannot tell the SoC from the image; pass --soc (e.g. --soc t31x)")
    return m.group(0), m.group(1)


def spi_nand(image):
    """Whether the image boots from SPI NAND: the boot ROM reads that
    from byte 8 of the SPL header, 0x00 for NAND, 0xaa for NOR."""
    with open(image, "rb") as f:
        head = f.read(9)
    return len(head) == 9 and head[:4] == b"\x06\x05\x04\x03" and not head[8]


def pad_nand(flash):
    """Fill the copy out to the whole chip, erased, so what the guest
    writes past the image (UBI grows into it) outlasts QEMU."""
    size = os.path.getsize(flash)
    if size > NAND_SIZE:
        die(f"the image is larger than the emulated {NAND_SIZE >> 20} MiB "
            f"SPI NAND")
    with open(flash, "ab") as f:
        while size < NAND_SIZE:
            n = min(NAND_SIZE - size, 1 << 20)
            f.write(b"\xff" * n)
            size += n


def soc_type(family):
    """The device -global soc-variant= applies to."""
    return {"t40": "ingenic-t40", "t41": "ingenic-t40",
            "a1": "ingenic-a1"}.get(family, "ingenic-t31")


def sfc_type(family):
    """The flash controller device -global nand-id= applies to."""
    return ("ingenic-a1-sfc" if family in ("t40", "t41", "a1")
            else "ingenic-t31-sfc")


_GPIO_TRACE = {}
_DEVICES = {}
_PROPS = {}


def gpio_trace_supported(qemu):
    """Whether this QEMU can log pin changes (ingenic-gpio's trace)."""
    if qemu not in _GPIO_TRACE:
        try:
            out = subprocess.run([qemu, "-device", "ingenic-gpio,help"],
                                 capture_output=True, text=True,
                                 timeout=30).stdout
        except (OSError, subprocess.TimeoutExpired):
            out = ""
        _GPIO_TRACE[qemu] = "trace=" in out
    return _GPIO_TRACE[qemu]


def qemu_devices(qemu):
    """The device types this QEMU has."""
    if qemu not in _DEVICES:
        try:
            out = subprocess.run([qemu, "-M", "none", "-device", "help"],
                                 capture_output=True, text=True,
                                 timeout=30).stdout
        except (OSError, subprocess.TimeoutExpired):
            out = ""
        _DEVICES[qemu] = set(re.findall(r'^name "([^"]+)"', out, re.M))
    return _DEVICES[qemu]


def qemu_device_props(qemu, model):
    """The properties of one of this QEMU's device types."""
    if (qemu, model) not in _PROPS:
        try:
            out = subprocess.run([qemu, "-M", "none", "-device",
                                  f"{model},help"], capture_output=True,
                                 text=True, timeout=30).stdout
        except (OSError, subprocess.TimeoutExpired):
            out = ""
        _PROPS[qemu, model] = set(re.findall(r"^\s+([\w-]+)=", out, re.M))
    return _PROPS[qemu, model]


def wifi_model(image, cfg, explicit):
    """The model of the camera's Wi-Fi: --wifi-chip, else the build's
    .config, else the Wi-Fi in the camera name (release images)."""
    if explicit:
        return explicit
    names = sorted((k[len("BR2_PACKAGE_WIFI_"):].lower()
                    for k, v in cfg.items()
                    if k.startswith("BR2_PACKAGE_WIFI_") and v == "y"),
                   key=len, reverse=True)       # ATBM6132CU_6162 first
    names += re.split(r"[_.+-]", os.path.basename(image).lower())
    hits = [WIFI_CHIPS[n] for n in names if n in WIFI_CHIPS]
    if not hits:
        die("no Wi-Fi model for this image; pass --wifi-chip ("
            + ", ".join(sorted(set(WIFI_CHIPS.values()))) + ")")
    return hits[0]


def card_detect(image, explicit):
    """(port, pin) of the SD slot's card-detect switch, which holds the pin
    low while a card is in: --sd-cd, else gpio.mmc_cd in the camera's
    thingino.json (a bare number is active low, as U-Boot and S09mmc take
    it), else MSC0's in the image's own device tree (stock 4.4 firmware).
    None when there is none, or it reads high with a card in."""
    if explicit:
        return None if explicit == "none" else gpio_pin(explicit)
    m = re.fullmatch(r"thingino-(.+)\.bin", os.path.basename(image))
    found = glob.glob(os.path.join(REPO_ROOT, "configs", "cameras*",
                                   m.group(1), "thingino.json")) if m else []
    try:
        with open(found[0]) as f:
            cd = json.load(f).get("gpio", {}).get("mmc_cd")
    except (IndexError, OSError, ValueError, AttributeError):
        cd = None
    if isinstance(cd, dict):
        if cd.get("active_low") is False:
            return None
        cd = cd.get("pin")
    if isinstance(cd, int) and not isinstance(cd, bool) and cd >= 0:
        return cd // 32, cd % 32
    tree = msc0_card_detect(image)
    if tree:
        return tree[:2] if tree[2] else None
    if not found:
        print(f"{PROG}: no card-detect pin known for this image; if the "
              f"firmware waits for one, pass --sd-cd PIN", file=sys.stderr)
    return None


def find_qemu(image, explicit):
    """--qemu or QEMU_BIN, else the QEMU package/qemu-ingenic pins: the
    one built beside the image if the build used that pin (a build tree
    keeps the QEMU of its day), else the release, fetched once."""
    if explicit or os.environ.get("QEMU_BIN"):
        return explicit or os.environ["QEMU_BIN"]
    pkg = os.path.join(REPO_ROOT, "package", "qemu-ingenic")
    with open(os.path.join(pkg, "qemu-ingenic.mk")) as f:
        mk = f.read()
    version = re.search(r"^QEMU_INGENIC_VERSION = (\S+)", mk, re.M).group(1)
    out = os.path.dirname(os.path.dirname(image))
    if os.path.isdir(os.path.join(out, "build",
                                  f"host-qemu-ingenic-{version}")):
        for bindir in ("host/bin", "per-package/host-qemu-ingenic/host/bin"):
            q = os.path.join(out, bindir, "qemu-system-mipsel")
            if os.access(q, os.X_OK):
                return q
    site = re.search(r"^QEMU_INGENIC_SITE = (\S+)", mk, re.M).group(1)
    return fetch_qemu(pkg, version,
                      site.replace("$(QEMU_INGENIC_VERSION)", version))


def fetch_qemu(pkg, version, site):
    """The pinned release, checked against the package's hash."""
    arch = {"x86_64": "x86_64", "amd64": "x86_64", "aarch64": "aarch64",
            "arm64": "aarch64"}.get(platform.machine().lower())
    asset = f"qemu-system-mipsel-linux-{arch}.tar.gz"
    sha = None
    with open(os.path.join(pkg, "qemu-ingenic.hash")) as f:
        for line in f:
            words = line.split()
            if len(words) == 3 and words[2] == asset:
                sha = words[1]
    if not sha:
        die(f"no QEMU release for {platform.machine()} hosts; pass --qemu")
    cache = os.path.join(os.environ.get("XDG_CACHE_HOME")
                         or os.path.expanduser("~/.cache"),
                         "thingino", "qemu-ingenic", version)
    q = os.path.join(cache, "qemu-system-mipsel")
    if os.access(q, os.X_OK):
        return q
    import urllib.request
    url = f"{site}/{asset}"
    print(f"fetching QEMU {version} into {cache}", file=sys.stderr)
    os.makedirs(cache, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=cache) as tmp:
        tgz = os.path.join(tmp, asset)
        with urllib.request.urlopen(url, timeout=60) as r, \
                open(tgz, "wb") as f:
            shutil.copyfileobj(r, f)
        with open(tgz, "rb") as f:
            got = hashlib.sha256(f.read()).hexdigest()
        if got != sha:
            die(f"{url}: sha256 {got}, expected {sha}")
        unpacked = os.path.join(tmp, "x")
        with tarfile.open(tgz) as t:
            if hasattr(tarfile, "data_filter"):
                t.extractall(unpacked, filter="data")
            else:
                t.extractall(unpacked)
        # The release tarballs lose the mode bits
        os.chmod(os.path.join(unpacked, "qemu-system-mipsel"), 0o755)
        for name in os.listdir(unpacked):
            dest = os.path.join(cache, name)
            if os.path.isdir(dest):
                shutil.rmtree(dest)
            os.replace(os.path.join(unpacked, name), dest)
    return q


def free_port(prefer=None):
    for port in ([prefer] if prefer else []) + [0]:
        with socket.socket() as s:
            try:
                s.bind(("127.0.0.1", port))
            except OSError:
                continue
            return s.getsockname()[1]


class Console(QemuSerial):
    """QemuSerial's guest state machine on a session's console, through
    its relay. QEMU writes the transcript itself, attached or not."""

    def __init__(self, sock):
        self.sock = sock
        self.fd = sock.fileno()
        self.log = None
        self._dsr_tail = b""
        self._utf8 = codecs.getincrementaldecoder("utf-8")(errors="replace")
        self.state = "boot"
        self.timeout_ok = None

    def _take(self, timeout):
        """What has arrived within timeout, at most one read of it."""
        if not select.select([self.fd], [], [], timeout)[0]:
            return ""
        try:
            chunk = os.read(self.fd, 65536)
        except OSError:
            chunk = b""
        if not chunk:
            raise EOFError("QEMU closed the console")
        # Answer the shell's terminal size probes, as QemuSerial does
        scan = self._dsr_tail + chunk
        for _ in range(scan.count(b"\x1b[6n")):
            self.write("\x1b[40;120R")
        self._dsr_tail = scan[-3:]
        return self._utf8.decode(chunk)

    def drain(self):
        """Take whatever has already arrived, without waiting for more."""
        while self._take(0):
            pass

    def read(self, timeout=2.0):
        buf = ""
        while True:
            chunk = self._take(timeout)
            if not chunk:
                return buf
            buf += chunk
            timeout = 0.3

    def wait_for_re(self, pattern, timeout=30):
        """As QemuSerial's, but it returns as soon as pattern arrives."""
        rx = re.compile(pattern)
        buf, pos = "", 0
        deadline = time.time() + timeout
        while True:
            m = rx.search(buf, pos)
            if m:
                return m, buf
            pos = max(0, len(buf) - 256)
            left = deadline - time.time()
            if left <= 0:
                return None, buf
            buf += self._take(min(left, 1.0))

    def wait_for(self, pattern, timeout=120):
        m, buf = self.wait_for_re(re.escape(pattern), timeout)
        return bool(m), buf

    def write(self, s):
        data = s.encode()
        while data:
            data = data[os.write(self.fd, data):]

    def close(self):
        self.sock.close()


class Session:
    def __init__(self, name):
        self.name = name
        self.dir = os.path.join(state_root(), name)
        self.info = {}

    def path(self, leaf):
        return os.path.join(self.dir, leaf)

    def load(self):
        with open(self.path("session.json")) as f:
            self.info = json.load(f)
        return self

    def save(self):
        tmp = self.path("session.json.tmp")
        with open(tmp, "w") as f:
            json.dump(self.info, f, indent=2)
        os.replace(tmp, self.path("session.json"))

    @property
    def log(self):
        return self.path(f"uart{self.info.get('uart', 1)}.log")

    def log_size(self):
        try:
            return os.path.getsize(self.log)
        except OSError:
            return 0

    def log_bytes(self, offset):
        try:
            with open(self.log, "rb") as f:
                f.seek(offset)
                return f.read()
        except OSError:
            return b""

    def log_since(self, offset):
        return self.log_bytes(offset).decode(errors="replace")

    def alive(self):
        # The command line names this session's directory, which a
        # recycled pid's would not
        try:
            with open(f"/proc/{self.info['pid']}/cmdline", "rb") as f:
                return self.dir.encode() in f.read()
        except (OSError, KeyError):
            return False

    @contextlib.contextmanager
    def locked(self, wait):
        """One command at a time types into the console."""
        fh = open(self.path("lock"), "w")
        deadline = time.time() + wait
        while True:
            try:
                fcntl.flock(fh, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.time() > deadline:
                    fh.close()
                    die(f"{self.name}: the console is busy (another "
                        f"command, or an attached console)")
                time.sleep(0.2)
        try:
            if os.path.exists(self.path("session.json")):
                self.load()
            yield
        finally:
            fh.close()

    def connect(self):
        """The console, through the relay; a relay that has gone (or a
        session from before relays) is started again."""
        for attempt in (0, 1):
            sock = socket.socket(socket.AF_UNIX)
            try:
                sock.connect(self.path("console"))
                break
            except OSError:
                sock.close()
                if attempt:
                    raise
                start_relay(self)
        con = Console(sock)
        con.timeout_ok = self.info.get("timeout_ok")
        return con

    @contextlib.contextmanager
    def console(self, wait):
        with self.locked(wait):
            if not self.alive():
                die(f"{self.name}: QEMU has exited; see `{PROG} log "
                    f"{self.name}`")
            con = self.connect()
            try:
                yield con
            finally:
                con.close()


def relay(name):
    """Hold a session's console pty open for as long as QEMU runs and pass
    it to one command at a time over a unix socket. QEMU stops reading a
    pty for up to a second whenever its last reader closes it, and every
    command would. With no command attached the output is dropped here;
    QEMU logs it anyway."""
    s = Session(name).load()
    pty = os.open(s.info["pty"][str(s.info["uart"])], os.O_RDWR | os.O_NOCTTY)
    with contextlib.suppress(FileNotFoundError):
        os.unlink(s.path("console"))
    srv = socket.socket(socket.AF_UNIX)
    srv.bind(s.path("console"))
    srv.listen(4)
    client = None
    while True:
        ready = select.select([pty, srv] + ([client] if client else []),
                              [], [])[0]
        if pty in ready:
            try:
                data = os.read(pty, 65536)
            except OSError:
                data = b""
            if not data:
                return                          # QEMU has gone
            if client:
                try:
                    client.sendall(data)
                except OSError:
                    client.close()
                    client = None
        if srv in ready:
            if client:
                client.close()
            client = srv.accept()[0]
        elif client and client in ready:
            try:
                data = client.recv(65536)
            except OSError:
                data = b""
            if not data:
                client.close()
                client = None
            while data:
                data = data[os.write(pty, data):]


def start_relay(s):
    with contextlib.suppress(FileNotFoundError):
        os.unlink(s.path("console"))
    with open(s.path("relay.log"), "wb") as log:
        p = subprocess.Popen(
            [sys.executable, "-c", "import sys; sys.path.insert(0, "
             "sys.argv[1]); from qemutest.dev import relay; "
             "relay(sys.argv[2])", SCRIPT_DIR, s.name],
            stdin=subprocess.DEVNULL, stdout=log, stderr=log,
            start_new_session=True)
    deadline = time.time() + 10
    while not os.path.exists(s.path("console")):
        if p.poll() is not None or time.time() > deadline:
            die(f"{s.name}: the console relay did not start; see "
                f"{s.path('relay.log')}")
        time.sleep(0.02)
    s.info["relay"] = p.pid
    s.save()


def stop_relay(s):
    with contextlib.suppress(OSError, KeyError, TypeError):
        with open(f"/proc/{s.info['relay']}/cmdline", "rb") as f:
            if b"qemutest.dev" in f.read():
                os.kill(s.info["relay"], signal.SIGTERM)


def follow_kernel(s, con, timeout):
    """The console the shell is on: U-Boot can print on one UART and
    Linux on the other, so the relay moves to whichever the kernel's banner
    reaches. Returns the console to use."""
    deadline = time.time() + timeout
    while time.time() < deadline:
        for k in (0, 1):
            with contextlib.suppress(OSError):
                with open(s.path(f"uart{k}.log"), "rb") as f:
                    if b"Linux version" not in f.read():
                        continue
                if k == s.info["uart"]:
                    return con
                con.close()
                stop_relay(s)
                s.info["uart"] = k
                s.save()
                start_relay(s)
                return s.connect()
        time.sleep(0.2)
    return con


def sessions():
    root = state_root()
    for name in sorted(os.listdir(root)) if os.path.isdir(root) else ():
        s = Session(name)
        try:
            yield s.load()
        except (OSError, ValueError):
            continue


def pick(name, live=True):
    if name:
        s = Session(name)
        try:
            s.load()
        except OSError:
            die(f"no session {name} (see `{PROG} ls`)")
        if live and not s.alive():
            die(f"{name}: QEMU has exited; see `{PROG} log {name}`, then "
                f"`{PROG} down {name}`")
        return s
    found = [s for s in sessions() if not live or s.alive()]
    if len(found) == 1:
        return found[0]
    if not found:
        die(f"no session; start one with `{PROG} up CAMERA`")
    die("several sessions (" + ", ".join(s.name for s in found)
        + "); name one")


def qmp(s, command, **args):
    q = Qmp(s.path("qmp"))
    try:
        return q.cmd(command, **args)
    finally:
        q.close()


def stop(s):
    # The relay ends with QEMU; this is for one whose QEMU was killed
    stop_relay(s)
    if not s.alive():
        return
    try:
        qmp(s, "quit")
    except Exception:
        pass
    for sig in (None, signal.SIGTERM, signal.SIGKILL):
        if sig:
            with contextlib.suppress(ProcessLookupError):
                os.kill(s.info["pid"], sig)
        for _ in range(30):
            if not s.alive():
                return
            time.sleep(0.1)


def ssh_argv(s):
    return ["ssh", "-p", str(s.info["ports"]["ssh"]),
            "-i", s.path("id_ed25519"), *SSH_OPTS, "root@127.0.0.1"]


def ssh_exec(s, cmd, timeout, stdin=subprocess.DEVNULL, stdout=None):
    """(rc, stderr); stdout streams to ours unless redirected. A camera
    that resets takes its end of the connection with it and ssh would
    wait out the timeout, so the console decides that one."""
    p = subprocess.Popen(ssh_argv(s) + [cmd], stdin=stdin, stdout=stdout,
                         stderr=subprocess.PIPE)
    deadline = time.time() + timeout
    pos, seen = s.log_size(), b""
    while True:
        try:
            _, err = p.communicate(timeout=0.5)
            return p.returncode, err
        except subprocess.TimeoutExpired:
            pass
        more = s.log_bytes(pos)
        pos += len(more)
        seen = seen[-32:] + more
        if re.search(RESET.encode(), seen) or time.time() > deadline:
            p.kill()
            p.communicate()
            if time.time() > deadline:
                return 124, b"(timed out)\n"
            return 255, b"(the camera rebooted)\n"


def ssh_unreachable(rc, err):
    """ssh never reached the camera, so the command did not run. A
    connection lost mid-command is not this: the command may have run."""
    return rc == 255 and re.search(
        rb"ssh: connect to host|kex_exchange_identification|"
        rb"Connection closed by \S+ port", err)


def serial_run(con, cmd, timeout):
    """Run cmd on the console: (rc, output), 124 on a timeout, 255 if the
    camera resets under it and REBOOTED if it reset before cmd started.
    The camera's own timeout ends a command that overruns: Ctrl-C cannot,
    as the console is no controlling terminal. The markers are split in
    the typed line so its echo never matches them."""
    tag = secrets.token_hex(4)
    run = f"sh -c {shlex.quote(cmd)}"
    if con.timeout_ok:
        run = f"timeout -s KILL {timeout} {run}"
    elif con.timeout_ok is None:
        run = (f"t=; timeout -s KILL 1 true 2>/dev/null && "
               f"t='timeout -s KILL {timeout}'; $t {run}")
    line = (f"printf '\\n%s%s\\n' QD{tag} B; {run} </dev/null; "
            f"printf '\\n%s%s %s\\n' QD{tag} E $?")
    if len(line) > MAX_LINE:
        script = f"/tmp/.qemu-dev-{tag}"
        if serial_upload(con, cmd.encode() + b"\n", script, timeout):
            return 124, "(could not send the command)\n"
        return serial_run(con, f". {script}; rc=$?; rm -f {script}; "
                               f"exit $rc", timeout)
    con.drain()
    t0 = time.time()
    con.write(line + "\n")
    m, buf = con.wait_for_re(rf"QD{tag}E (\d+)\r?\n|{RESET}", timeout + 15)
    start = re.search(rf"QD{tag}B\r?\n", buf)
    out = clean(buf[start.end():m.start() if m else len(buf)]) if start else ""
    if m and not m.group(1):
        return (255 if start else REBOOTED), out
    if not m:
        return 124, out
    rc = int(m.group(1))
    if rc == 137 and time.time() - t0 >= timeout:
        rc = 124
    # The end marker's own leading newline
    return rc, out[:-1] if out.endswith("\n") else out


def serial_upload(con, data, remote, timeout):
    """Write data to a file on the camera, one line of base64 per shell
    command; returns the exit status. The console has no flow control:
    a stream outruns the camera's tty buffer, so each line waits for the
    shell to take the last. Nothing goes out while the shell switches the
    terminal mode, either: what arrives then is lost."""
    tag = secrets.token_hex(4)
    part = f"/tmp/.qemu-dev-{tag}"
    deadline = time.time() + timeout
    b64 = base64.b64encode(data).decode()
    con.drain()
    con.write(f"stty -echo; printf '%s%s\\n' QD{tag} S\n")
    if not con.wait_for_re(rf"QD{tag}S\r?\n", 15)[0]:
        return 124
    rc = 124
    for i in range(0, max(len(b64), 1), 800):
        con.write(f"printf %s {b64[i:i + 800]} >> {part}; "
                  f"printf '%s%s\\n' QD{tag} K{i}\n")
        if not con.wait_for_re(rf"QD{tag}K{i}\r?\n",
                               max(deadline - time.time(), 1))[0]:
            break
    else:
        con.write(f"base64 -d {part} > {shlex.quote(remote)}; "
                  f"printf '%s%s %s\\n' QD{tag} E $?\n")
        m, _ = con.wait_for_re(rf"QD{tag}E (\d+)\r?\n",
                               max(deadline - time.time(), 10))
        rc = int(m.group(1)) if m else 124
    con.write(f"rm -f {part}; stty echo; printf '%s%s\\n' QD{tag} Z\n")
    con.wait_for_re(rf"QD{tag}Z\r?\n", 15)
    return rc


def attach_network(s, con):
    """Point the host forwards at the camera's slirp address and install
    the session's key, so file copies go over SSH. The address can change
    from boot to boot (the MAC does), so this runs after every login. A
    wired interface carries them if it has an address, else the Wi-Fi, else
    the setup portal for --portal's phone."""
    s.info["ssh"] = False
    if not s.info.get("ports"):
        return
    wifi = s.info.get("wifi") or {}
    joins = False                           # set up to join the AP
    if wifi.get("ssid"):
        conf = shlex.quote(f'ssid="{wifi["ssid"]}"')
        rc, _ = serial_run(con, f"grep -qF {conf} /etc/wpa_supplicant.conf",
                           20)
        joins = rc == 0
    ip = netdev = None
    deadline = time.time() + (60 if joins else 30)
    while time.time() < deadline:
        _, out = serial_run(con, "ip -4 -o addr show; "
                                 "cat /sys/class/net/eth*/operstate", 20)
        found = re.findall(r"^\d+: (\S+)\s+inet ([\d.]+)/", out, re.M)
        wired = [a for i, a in found
                 if not i.startswith("wlan") and a.startswith("10.0.2.")]
        wlan = [a for i, a in found
                if i.startswith("wlan") and a.startswith("10.0.2.")]
        # the HI3881 runs its portal on ap0
        portal = wifi.get("portal") and any(
            i.startswith(("wlan", "ap")) and a == PORTAL_IP
            for i, a in found)
        if wired or (joins and wlan):
            ip, netdev = (wired[0], "n0") if wired else (wlan[0], "w0")
            break
        if portal and not joins:
            ip, netdev = PORTAL_IP, "c0"
            break
        if not (joins or wifi.get("portal")) and \
                not re.search(r"^(up|unknown)$", out, re.M):
            break                           # no wired interface up
        time.sleep(2)
    if not ip:
        return
    q = Qmp(s.path("qmp"))
    try:
        for svc, port in s.info["ports"].items():
            if s.info.get("guest_ip"):
                q.cmd("human-monitor-command", **{
                    "command-line": "hostfwd_remove "
                    f"{s.info.get('fwd_netdev', 'n0')} tcp:127.0.0.1:{port}"})
            guest = GUEST_PORTS.get(svc) or int(svc)
            err = q.cmd("human-monitor-command", **{
                "command-line": f"hostfwd_add {netdev} tcp:127.0.0.1:{port}-"
                                f"{ip}:{guest}"})
            if err.strip():
                print(f"{PROG}: forwarding {svc}: {err.strip()}",
                      file=sys.stderr)
    finally:
        q.close()
    s.info["guest_ip"] = ip
    s.info["fwd_netdev"] = netdev
    if not (shutil.which("ssh") and os.path.exists(s.path("id_ed25519"))):
        return
    with open(s.path("id_ed25519.pub")) as f:
        pub = shlex.quote(f.read().strip())
    serial_run(con, f"mkdir -p /root/.ssh && chmod 700 /root/.ssh && "
                    f"{{ grep -qxF {pub} /root/.ssh/authorized_keys || "
                    f"echo {pub} >> /root/.ssh/authorized_keys; }} "
                    f"2>/dev/null", 20)
    deadline = time.time() + 30
    while time.time() < deadline:
        if ssh_exec(s, "true", 15, stdout=subprocess.DEVNULL)[0] == 0:
            s.info["ssh"] = True
            return
        time.sleep(2)


def boot_to_shell(s, con, timeout):
    """Log in on the console and set the session up for commands."""
    if not con.login(timeout, passwords=(s.info["password"],)):
        return False
    rc, _ = serial_run(con, "timeout -s KILL 1 true", 20)
    s.info["timeout_ok"] = con.timeout_ok = rc == 0
    attach_network(s, con)
    s.info.update(state="shell", mark=s.log_size())
    s.save()
    return True


def join_wifi(s, ssid, psk, timeout):
    """Set the camera up to join the access point and reboot it onto it,
    unless it already is: thingino picks its Wi-Fi mode at boot."""
    conf = shlex.quote(f'ssid="{ssid}"')
    with s.console(timeout) as con:
        rc, _ = serial_run(con, f"grep -qF {conf} /etc/wpa_supplicant.conf",
                           20)
        if rc == 0:
            return
        rc, out = serial_run(con, f"wlan configure {shlex.quote(ssid)} "
                                  f"{shlex.quote(psk)}", 60)
        if rc:
            die(f"{s.name}: wlan configure failed: {out.strip()}")
        con.drain()
        con.write("reboot\n")
        con.read(0.5)
        con.state = "rebooting"
        s.info.update(state="booting", ssh=False)
        s.save()
        if not boot_to_shell(s, con, timeout):
            die(f"{s.name}: no shell after setting up the Wi-Fi "
                f"(`{PROG} log {s.name}`)", 2)


def stop_in_uboot(s, con, timeout, gated):
    """Interrupt autoboot and stop at the U-Boot prompt. gated: a reset
    is on its way, so nothing is sent before its banner (a Ctrl-C into
    the shell that is running reboot could stop the reboot)."""
    deadline = time.time() + timeout
    buf = ""
    while time.time() < deadline:
        if not gated:
            con.write("\x03")
        buf += con.read(0.1)
        text = clean(buf)
        if gated:
            if re.search(r"U-Boot SPL|Restarting system", text):
                gated, buf = False, ""
            continue
        if "Starting kernel" in text:
            return False
        m = UBOOT_PROMPT.search(text)
        if m:
            con.read(0.5)               # the last Ctrl-Cs' own prompts
            s.info.update(state="uboot", uboot_prompt=m.group(1),
                          mark=s.log_size(), ssh=False)
            s.save()
            return True
    return False


def console_text(s):
    """The console log, cleaned, and its last reset banner."""
    text = clean(s.log_since(0))
    last = None
    for last in BANNER.finditer(text):
        pass
    return text, last


def uboot_prompt(text, last):
    """The U-Boot prompt the console log ends at, if it ends at one."""
    m = UBOOT_PROMPT.search(text)
    return m.group(1) if m and last and last.group(0) == "U-Boot SPL" else None


def needs_settle(s):
    return (s.info.get("state") != "shell"
            or BANNER.search(s.log_since(s.info.get("mark", 0))))


def settle(s, con, timeout):
    """Bring a session back to a logged-in shell after a boot it did not
    drive: up --no-wait, a crash, a watchdog, reboot run over sh."""
    deadline = time.time() + timeout
    while True:
        text, last = console_text(s)
        if last and last.group(0) == "Starting kernel":
            break
        prompt = uboot_prompt(text, last)
        if prompt:
            s.info.update(state="uboot", uboot_prompt=prompt,
                          mark=s.log_size(), ssh=False)
            s.save()
            die(f"{s.name} is at the U-Boot prompt: `{PROG} uboot "
                f"{s.name} -- boot` or `{PROG} reboot {s.name}`")
        if time.time() > deadline:
            die(f"{s.name}: still booting after {timeout} s", 124)
        con.read(1.0)
    # A prompt that went by before we attached will not come again
    tail = text[last.end():]
    if PROMPT.search(tail) or re.search(r"login: *$", tail, re.M):
        con.write("\n")
    con.state = "boot"
    if not boot_to_shell(s, con, max(deadline - time.time(), 30)):
        die(f"{s.name}: no shell on the console (`{PROG} log {s.name}`)", 124)


def ensure_shell(s, timeout):
    if needs_settle(s):
        with s.console(timeout) as con:
            if needs_settle(s):
                settle(s, con, timeout)


def describe(s, as_json=False):
    i = s.info
    state = i.get("state") if s.alive() else "dead"
    ports = i.get("ports") or {}
    view = {k: i.get(k) for k in ("name", "machine", "variant", "model",
                                  "image", "qemu", "pid", "password")}
    view.update(state=state, ssh=bool(i.get("ssh")), console_log=s.log)
    if i.get("ssh"):
        view["ssh_command"] = " ".join(shlex.quote(a) for a in ssh_argv(s))
    if ports and i.get("guest_ip") and state != "uboot":
        view.update(ports=ports, web=f"http://127.0.0.1:{ports['http']}/")
    if as_json:
        return json.dumps(view, indent=2)
    soc = i["machine"] + (f" {i['variant']}" if i.get("variant") else "")
    run = "uboot" if state == "uboot" else "sh"
    out = [f"{s.name}: {state} ({soc}, pid {i['pid']})",
           f"  image    {i['image']}",
           f"  run      {PROG} {run} {s.name} -- <command>"]
    if "ssh_command" in view:
        out.append(f"  ssh      {view['ssh_command']}")
    if "web" in view and i.get("fwd_netdev") == "c0":
        out.append(f"  portal   {view['web']}  (the camera's setup page)")
    elif "web" in view:
        out.append(f"  web      {view['web']}  https://127.0.0.1:"
                   f"{ports['https']}/  (root / {i['password']})")
        extra = [f"{port} -> {svc}" for svc, port in ports.items()
                 if svc not in GUEST_PORTS]
        if extra:
            out.append("  forwards " + ", ".join(extra))
    elif i.get("state") == "shell":
        out.append("  network  none: no wired interface, so files go over "
                   "the serial console too")
    w = i.get("wifi")
    if w and i.get("fwd_netdev") == "c0" and i.get("ssh"):
        out.append(f"  wifi     {w['model']}, running the setup portal a "
                   f"phone has joined (forwards go over it)")
    elif w and i.get("fwd_netdev") == "c0":
        out.append(f"  wifi     {w['model']}, running the setup portal; SSH "
                   f"did not get through the phone, so files go over the "
                   f"serial console")
    elif w and w.get("ssid"):
        out.append(f"  wifi     {w['model']}, on the access point "
                   f"{w['ssid']}" + (" (forwards go over it)"
                                     if i.get("fwd_netdev") == "w0" else ""))
    elif w:
        out.append(f"  wifi     {w['model']}")
    out.append(f"  console  {s.log}")
    return "\n".join(out)


def cmd_images(args):
    rows = []
    for img in built_images():
        cfg = read_config(img)
        model = cfg.get("BR2_INGENIC_SOC_MODEL", "?")
        m = SOC.fullmatch(model)
        machine = SOC_MACHINES.get(m.group(1) if m else "", ("-",))[0]
        age = (time.time() - os.path.getmtime(img)) / 3600
        name = os.path.basename(img)[len("thingino-"):-len(".bin")]
        rows.append({"camera": name, "soc": model, "machine": machine,
                     "built_hours_ago": round(age, 1), "image": img})
    if args.json:
        print(json.dumps(rows, indent=2))
        return 0
    if not rows:
        print("no built images (build one with `make CAMERA=<camera> fast`)")
        return 0
    w = max(len(r["camera"]) for r in rows)
    print(f"{'CAMERA':<{w}}  {'SOC':<6} {'MACHINE':<12} {'AGE':>8}  IMAGE")
    for r in rows:
        print(f"{r['camera']:<{w}}  {r['soc']:<6} {r['machine']:<12} "
              f"{r['built_hours_ago']:>6.1f} h  {r['image']}")
    return 0


def cmd_up(args, extra):
    if args.console:
        args.no_wait = True
    if args.no_wait and args.uboot:
        die("--uboot needs to watch the boot, so it cannot be --no-wait")
    image = resolve_image(args.target)
    cfg = read_config(image)
    model, family = resolve_soc(image, cfg, args.soc)
    machine, ram = SOC_MACHINES.get(family, (None, None))
    machine = args.machine or machine
    if not machine:
        die(f"no QEMU machine for {model}; pass --machine")
    nand = spi_nand(image)
    if args.variant is not None:
        variant = args.variant or None
    else:
        variant = model if model in FORK_VARIANTS else None
    camera = re.sub(r"^thingino-|\.bin$", "", os.path.basename(image))
    name = args.name or camera
    if not re.fullmatch(r"[\w.+-]+", name):
        die(f"bad session name {name!r}; pass --name")
    qemu = find_qemu(image, args.qemu)
    wifi = None
    if args.wifi or args.portal:
        ssid, _, psk = (args.wifi or "").partition(":")
        if args.wifi and (not ssid or not 8 <= len(psk) <= 63):
            die("--wifi wants SSID:PASSPHRASE, a passphrase of 8 to 63 "
                "characters")
        wifi = {"model": wifi_model(image, cfg, args.wifi_chip),
                "ssid": ssid or None, "portal": args.portal}
        if wifi["model"] not in qemu_devices(qemu):
            die(f"{qemu} has no {wifi['model']} model; pass --qemu with "
                f"ingenic-0.6.16 or a newer build of the fork")
        if args.portal and \
                "client-netdev" not in qemu_device_props(qemu, wifi["model"]):
            die(f"{qemu} has no Wi-Fi client for --portal; pass --qemu "
                f"with ingenic-0.6.16 or a newer build of the fork")

    s = Session(name)
    old_ports = {}
    if os.path.exists(s.path("session.json")):
        s.load()
        old_ports = s.info.get("ports") or {}
        if s.alive():
            print(f"replacing the running {name} session", file=sys.stderr)
            stop(s)
    os.makedirs(s.dir, mode=0o700, exist_ok=True)
    if len(s.path("qmp")) > 107:
        die(f"{s.dir} is too long for a unix socket; set QEMU_DEV_DIR")
    flash = s.path("flash.bin")
    if not (args.keep and os.path.exists(flash)):
        shutil.copyfile(image, flash)
        if nand:
            pad_nand(flash)
    for leaf in ("qmp", "uart0.log", "uart1.log"):
        with contextlib.suppress(FileNotFoundError):
            os.unlink(s.path(leaf))
    if shutil.which("ssh-keygen") and not os.path.exists(s.path("id_ed25519")):
        subprocess.run(["ssh-keygen", "-t", "ed25519", "-N", "", "-q",
                        "-C", f"qemu-dev-{name}", "-f", s.path("id_ed25519")],
                       check=True)
    ports = {}
    if args.net == "slirp":
        for svc in list(GUEST_PORTS) + [str(p) for p in args.fwd]:
            ports[svc] = free_port(old_ports.get(svc))

    argv = [qemu, "-M", machine, "-display", "none", "-S",
            "-qmp", f"unix:{s.path('qmp')},server=on,wait=off",
            "-drive", f"file={flash},format=raw,if=none,id=flash0"]
    # Most cameras talk on UART1, a few on UART0: give both a console
    # and keep whichever speaks first
    for n in (0, 1):
        argv += ["-chardev", f"pty,id=uart{n},"
                 f"logfile={s.path(f'uart{n}.log')}",
                 "-serial", f"chardev:uart{n}"]
    if args.ram or ram:
        argv += ["-m", f"{args.ram or ram}M"]
    if variant:
        argv += ["-global", f"{soc_type(family)}.soc-variant={variant}"]
    if nand:
        argv += ["-global", f"{sfc_type(family)}.nand-id={NAND_ID:#x}"]
    if gpio_trace_supported(qemu):
        argv += ["-chardev", f"file,id=gpiotrace,path={s.path('gpio.jsonl')}",
                 "-global", "ingenic-gpio.trace=gpiotrace"]
    if ports:
        argv += ["-netdev", "user,id=n0"]
    if wifi:
        bus = "msc1" if wifi["model"] in SDIO_WIFI else "usb-bus.0,port=1"
        dev = [wifi["model"], f"bus={bus}", "netdev=w0"]
        argv += ["-netdev", "user,id=w0"]
        if args.portal:
            mac = "52:55:" + ":".join(f"{int(b):02x}"
                                      for b in PORTAL_PHONE.split("."))
            argv += ["-netdev", f"user,id=c0,net={PORTAL_NET}.0/24,"
                     f"host={PORTAL_PHONE},ipv6=off"]
            dev += ["client-netdev=c0", f"client-mac={mac}"]
            # where the driver runs no open AP, the portal's passphrase
            # (package/wifi/wifi.mk) for the phone
            if "client-psk" in qemu_device_props(qemu, wifi["model"]):
                dev += [f"client-psk={PORTAL_PSK}"]
        # the passphrase last: the saved argv drops it from there on
        if args.wifi:
            dev += [f"{k}={v.replace(',', ',,')}"
                    for k, v in (("ssid", ssid), ("psk", psk))]
        argv += ["-device", ",".join(dev)]
    if args.sd:
        argv += ["-drive", f"if=sd,index=0,format=raw,"
                 f"file={os.path.abspath(args.sd)}"]
        cd = card_detect(image, args.sd_cd)
        if cd and "in-pa" in qemu_device_props(qemu, "ingenic-gpio"):
            port, pin = cd
            argv += ["-global", f"ingenic-gpio.in-p{chr(ord('a') + port)}="
                     f"{0xffffffff & ~(1 << pin):#x}"]
        elif cd:
            name = f"P{chr(ord('A') + cd[0])}{cd[1]}"
            print(f"{qemu} cannot hold the card-detect pin {name} low from "
                  f"the start (ingenic-0.6.17 can), so U-Boot will not see "
                  f"the card; `{PROG} gpio {name}=0` inserts it for Linux",
                  file=sys.stderr)
    argv += extra

    with open(s.path("qemu.log"), "wb") as log:
        proc = subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=log,
                                stderr=subprocess.STDOUT,
                                start_new_session=True)
    s.info = {"name": name, "pid": proc.pid, "image": image,
              "camera": camera, "model": model, "machine": machine,
              "variant": variant, "qemu": qemu, "ports": ports,
              "password": args.password
              or cfg.get("BR2_TARGET_GENERIC_ROOT_PASSWD") or "root",
              "state": "booting", "mark": 0, "uart": 1, "ssh": False,
              "wifi": wifi, "started": int(time.time()),
              "argv": [re.sub(r",psk=.*", ",psk=...", a) for a in argv]}
    s.save()

    def failed(what):
        with open(s.path("qemu.log"), errors="replace") as f:
            print(f.read()[-2000:], file=sys.stderr)
        die(f"QEMU {what}; the command was: {shlex.join(argv)}", 2)

    t0 = time.time()
    with s.locked(10):
        while not os.path.exists(s.path("qmp")):
            if proc.poll() is not None:
                failed("exited")
            if time.time() - t0 > 15:
                stop(s)
                failed("did not start")
            time.sleep(0.1)
        s.info["pty"] = {c["label"][-1]: c["filename"][len("pty:"):]
                         for c in qmp(s, "query-chardev")
                         if re.fullmatch(r"uart[01]", c["label"])}
        # thingino stops Wi-Fi on a camera whose wired port has a link
        if wifi:
            qmp(s, "set_link", name="n0", up=False)
        qmp(s, "cont")
        n = None
        while n is None:
            for k in (0, 1):
                with contextlib.suppress(OSError):
                    if os.path.getsize(s.path(f"uart{k}.log")):
                        n = k
                        break
            else:
                if proc.poll() is not None:
                    failed("exited")
                if time.time() - t0 > 30:
                    failed("printed nothing on UART0 or UART1 in 30 s")
                time.sleep(0.02)
        s.info["uart"] = n
        s.save()
        start_relay(s)
        con = s.connect()
        try:
            if args.no_wait:
                ok = True
            elif args.uboot:
                ok = stop_in_uboot(s, con, args.timeout, gated=False)
            else:
                con = follow_kernel(s, con, args.timeout)
                ok = boot_to_shell(s, con, args.timeout)
        finally:
            con.close()
    if not ok:
        print("\n".join(clean(s.log_since(0)).split("\n")[-30:]),
              file=sys.stderr)
        die(f"{name}: no {'U-Boot prompt' if args.uboot else 'shell'} in "
            f"{args.timeout} s; the session is left running for a look "
            f"(`{PROG} log`, `{PROG} console`, `{PROG} down {name}`)", 2)
    if args.wifi and not (args.portal or args.no_wait or args.uboot):
        join_wifi(s, ssid, psk, args.timeout)
    if not args.no_wait:
        print(f"{name}: up in {time.time() - t0:.0f} s", file=sys.stderr)
    print(describe(s, args.json))
    if args.console:
        args.name, args.all = name, True
        return cmd_console(args)
    return 0


def cmd_sh(args, cmd):
    s = pick(args.name)
    if not cmd:
        die("no command: sh [NAME] -- CMD...")
    cmd = " ".join(cmd)
    for retry in (False, True):
        with s.console(args.timeout) as con:
            if needs_settle(s):
                settle(s, con, args.timeout)
            rc, out = serial_run(con, cmd, args.timeout)
            rebooted = BANNER.search(s.log_since(s.info.get("mark", 0)))
            if not rebooted:
                s.info["mark"] = s.log_size()
                s.save()
        sys.stdout.write(out)
        if rc != REBOOTED:
            if rebooted:
                print(f"\n{PROG}: {s.name} rebooted under the command",
                      file=sys.stderr)
            return rc
        if retry:
            return 255
        # It was going down already: run it once it is back up
        print(f"{PROG}: {s.name} was rebooting; running the command once "
              f"it is back", file=sys.stderr)


def cmd_put(args):
    s = pick(args.name)
    with open(args.local, "rb") as f:
        data = f.read()
    mode = os.stat(args.local).st_mode & 0o777
    base = shlex.quote(os.path.basename(args.local))
    ensure_shell(s, args.timeout)
    if s.info.get("ssh"):
        with open(args.local, "rb") as f:
            rc, err = ssh_exec(
                s, f"f={shlex.quote(args.remote)}; [ -d \"$f\" ] && "
                   f"f=\"$f\"/{base}; cat > \"$f\" && chmod {mode:o} \"$f\"",
                args.timeout, stdin=f, stdout=subprocess.DEVNULL)
        if not ssh_unreachable(rc, err):
            if rc:
                die(err.decode(errors="replace").strip() or f"exit {rc}", rc)
            return 0
    with s.console(args.timeout) as con:
        if needs_settle(s):
            settle(s, con, args.timeout)
        remote = args.remote
        if serial_run(con, f"[ -d {shlex.quote(remote)} ]", 20)[0] == 0:
            remote = remote.rstrip("/") + "/" + os.path.basename(args.local)
        rc = serial_upload(con, data, remote, args.timeout)
        _, out = serial_run(con, f"chmod {mode:o} {shlex.quote(remote)} && "
                                 f"md5sum {shlex.quote(remote)}", 20)
        s.info["mark"] = s.log_size()
        s.save()
    if rc or hashlib.md5(data).hexdigest() not in out:
        die(f"copying to {remote} over the serial console failed "
            f"(exit {rc}): {out.strip()}")
    return 0


def cmd_get(args):
    s = pick(args.name)
    local = args.local
    if os.path.isdir(local):
        local = os.path.join(local, os.path.basename(args.remote))
    ensure_shell(s, args.timeout)
    if s.info.get("ssh"):
        part = local + ".part"
        with open(part, "wb") as f:
            rc, err = ssh_exec(s, f"cat {shlex.quote(args.remote)}",
                               args.timeout, stdout=f)
        if rc == 0:
            os.replace(part, local)
            return 0
        os.unlink(part)
        if not ssh_unreachable(rc, err):
            die(err.decode(errors="replace").strip() or f"exit {rc}", rc)
    q = shlex.quote(args.remote)
    with s.console(args.timeout) as con:
        if needs_settle(s):
            settle(s, con, args.timeout)
        rc, out = serial_run(con, f"base64 {q}", args.timeout)
        _, sums = serial_run(con, f"md5sum {q}", 20)
        s.info["mark"] = s.log_size()
        s.save()
    if rc:
        die(out.strip() or f"exit {rc}", rc)
    data = base64.b64decode("".join(out.split()))
    if hashlib.md5(data).hexdigest() not in sums:
        die(f"copying {args.remote} over the serial console came out wrong; "
            f"try again")
    with open(local, "wb") as f:
        f.write(data)
    return 0


def cmd_log(args):
    s = pick(args.name, live=False)
    text = s.log_since(0)
    text = text if args.raw else clean(text)
    if args.boot:
        starts = [m.start() for m in re.finditer(r"U-Boot SPL", text)]
        text = text[starts[-1]:] if starts else text
    lines = text.split("\n")
    if args.lines and not args.boot:
        lines = lines[-args.lines:]
    sys.stdout.write("\n".join(lines))
    if not args.follow:
        sys.stdout.write("\n")
        return 0
    try:
        with open(s.log, "rb") as f:
            f.seek(0, os.SEEK_END)
            while True:
                more = f.read().decode(errors="replace")
                if more:
                    sys.stdout.write(more if args.raw else clean(more))
                    sys.stdout.flush()
                time.sleep(0.5)
    except KeyboardInterrupt:
        return 0


def cmd_reboot(args):
    s = pick(args.name)
    with s.console(args.timeout) as con:
        t0 = time.time()
        if args.hard or needs_settle(s):
            qmp(s, "system_reset")
        else:
            con.drain()
            con.write("reboot\n")
            con.read(0.5)
        con.state = "rebooting"
        s.info.update(state="booting", ssh=False)
        s.save()
        if args.no_wait:
            print(f"{s.name}: rebooting")
            return 0
        if args.uboot:
            ok = stop_in_uboot(s, con, args.timeout, gated=True)
        else:
            ok = boot_to_shell(s, con, args.timeout)
    if not ok:
        die(f"{s.name}: no {'U-Boot prompt' if args.uboot else 'shell'} "
            f"after the reboot (`{PROG} log {s.name}`)", 2)
    print(f"{s.name}: {'U-Boot prompt' if args.uboot else 'shell'} in "
          f"{time.time() - t0:.0f} s")
    return 0


def cmd_uboot(args, cmd):
    s = pick(args.name)
    if not cmd:
        die("no command: uboot [NAME] -- CMD...")
    cmd = " ".join(cmd)
    with s.console(args.timeout) as con:
        if s.info.get("state") != "uboot":
            prompt = uboot_prompt(*console_text(s))
            if not prompt:
                die(f"{s.name} is not at the U-Boot prompt; get there with "
                    f"`{PROG} up --uboot` or `{PROG} reboot --uboot`")
            s.info.update(state="uboot", uboot_prompt=prompt, ssh=False)
        prompt = s.info["uboot_prompt"]
        # The status comes back on a marker line; a U-Boot without $?
        # echoes it literally, which reads as success
        tag = secrets.token_hex(4)
        con.drain()
        con.write(f"{cmd}; echo QD{tag} $?\n")
        t0 = deadline = time.time()
        deadline += args.timeout
        buf = ""
        while time.time() < deadline:
            buf += con.read(0.5)
            text = clean(buf)
            if "Starting kernel" in text:
                print(f"{PROG}: {s.name} is booting Linux", file=sys.stderr)
                con.state = "boot"
                s.info["state"] = "booting"
                s.save()
                if not boot_to_shell(s, con, max(deadline - time.time(), 300)):
                    die(f"{s.name}: no shell after the boot", 2)
                print(f"{s.name}: shell in {time.time() - t0:.0f} s")
                return 0
            if text.endswith(prompt) and "\n" in text:
                out = text[:-len(prompt)].split("\n", 1)[1]
                m = re.search(rf"^QD{tag} (\S*)\n?", out, re.M)
                rc = int(m.group(1)) if m and m.group(1).isdigit() else 0
                sys.stdout.write(out[:m.start()] + out[m.end():] if m else out)
                s.info["mark"] = s.log_size()
                s.save()
                return rc
        con.write("\x03")
        con.read(1.0)
    sys.stdout.write(clean(buf))
    die(f"no U-Boot prompt after {args.timeout} s", 124)


def cmd_send(args, words):
    """Type at the console as a person would: nothing is checked or
    logged in first. Prints everything the console showed meanwhile."""
    s = pick(args.name)
    text = unescape(" ".join(words))
    if args.repeat and not args.expect:
        die("--repeat needs --expect")
    show = (lambda t: t) if args.raw else clean
    deadline = time.time() + args.timeout
    missed = None
    with s.console(args.timeout) as con:
        start = s.log_size()
        buf = ""
        if args.after:
            m, buf = con.wait_for_re(args.after, args.timeout)
            if not m:
                missed = args.after
        due, sent = 0, len(buf)
        while not missed:
            now = time.time()
            if text and now >= due and (due == 0 or args.repeat):
                con.write(text)
                due = now + (args.repeat or 0)
            if not args.expect:
                buf += con.read(1.5)
                break
            if re.search(args.expect, show(buf[sent:])):
                break
            if now > deadline:
                missed = args.expect
                break
            buf += con._take(min(deadline - now, args.repeat or 1.0))
        # A reset or a logout ends the shell the session knew
        if (BANNER.search(clean(s.log_since(start)))
                or re.search(r"login: *$", clean(buf))):
            s.info["state"] = "unknown"
            s.save()
    # The tail is what an agent acts on; the rest stays in `log`
    lines = show(buf if missed else buf[sent:]).split("\n")
    if len(lines) > 40:
        print(f"({len(lines) - 40} lines before these: {PROG} log)",
              file=sys.stderr)
    sys.stdout.write("\n".join(lines[-40:]))
    if missed:
        print(f"\n{PROG}: {missed!r} not seen in {args.timeout} s",
              file=sys.stderr)
        return 124
    return 0


def cmd_monitor(args, words):
    s = pick(args.name)
    if not words:
        die("no command: monitor [NAME] -- COMMAND")
    sys.stdout.write(qmp(s, "human-monitor-command",
                         **{"command-line": " ".join(words)}))
    return 0


def gpio_pin(word):
    """(port, pin) from PB14 or a Linux GPIO number (46)."""
    m = re.fullmatch(r"p([a-f])(\d{1,2})", word.lower())
    if m and int(m.group(2)) < 32:
        return ord(m.group(1)) - ord("a"), int(m.group(2))
    if word.isdigit():
        return int(word) // 32, int(word) % 32
    die(f"not a pin: {word} (PB14 or a GPIO number)")


def gpio_mode(regs, b):
    """What a pin is, from its INT, MSK, PAT1 and PAT0 bits."""
    intr, msk, pat1, pat0 = ((regs[r] >> b) & 1
                             for r in ("int", "msk", "pat1", "pat0"))
    if intr:
        trig = ("low", "high", "falling", "rising")[pat1 << 1 | pat0]
        return f"irq {trig}" + (" masked" if msk else "")
    if msk:
        return "in" if pat1 else "out"
    return f"func{pat1 << 1 | pat0}"


def qom_props(q, path, want):
    """The properties at path, or a clear stop when this QEMU predates
    the one wanted."""
    try:
        props = {p["name"] for p in q.cmd("qom-list", path=path)}
    except RuntimeError:
        props = set()
    if want not in props:
        die(f"this QEMU cannot do that ({path} has no {want}); it needs "
            f"a qemu-ingenic release newer than ingenic-0.6.11")
    return props


def gpio_events(path, follow):
    """The pin changes QEMU logged, and while following, those to come."""
    with open(path) as f:
        part = ""
        while True:
            part += f.readline()
            if part.endswith("\n"):
                yield json.loads(part)
                part = ""
            elif follow:
                time.sleep(0.2)
            else:
                return


def gpio_event_mode(e):
    """A logged pin state in gpio_mode()'s words, with its level."""
    if e["fn"] == "func":
        return f"func{e['func']}"
    if e["fn"] == "irq":
        return (f"irq {e['trig']}" + (" masked" if e["mask"] else "")
                + f" {e['lvl']}")
    return f"{e['fn']} {e['lvl']}"


PINS_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "pins")


def pin_table(model):
    """The pins of a SoC from Ingenic's documents (make-pin-tables.py), by
    name: functions 0-3, state out of reset, packages; {} if none. The
    longest table name the model starts with wins: t32pro over t32."""
    try:
        names = [f[:-5] for f in os.listdir(PINS_DIR) if f.endswith(".json")]
        name = max((n for n in names if (model or "").startswith(n)),
                   key=len)
        with open(os.path.join(PINS_DIR, f"{name}.json")) as f:
            return json.load(f)["pins"]
    except (OSError, ValueError, KeyError):
        return {}


def gpio_print_log(events, pins):
    state = {}
    for e in events:
        if e.get("reset"):
            state.clear()
            print(f"{e['t'] / 1e9:11.6f}  reset")
            continue
        now = gpio_event_mode(e)
        if e["fn"] == "func":
            name = pins.get(e["pin"], {}).get("func", [""] * 4)[e["func"]]
            now += f" ({name})" if name else ""
        was = state.get(e["pin"], "reset state")
        state[e["pin"]] = now
        who = e.get("pc") or e.get("src", "")
        print(f"{e['t'] / 1e9:11.6f}  {e['pin']:<5}{e['gpio']:>4}  "
              f"{was} -> {now}  {who}", flush=True)


def gpio_write_vcd(events, path):
    """Each pin's level for a waveform viewer; z while in a device
    function; a reset wire pulses at each reset."""
    events = list(events)
    pins = list(dict.fromkeys(e["pin"] for e in events if "pin" in e))
    ids = {}
    for i, pin in enumerate(["reset"] + pins):
        n, code = i, ""
        while True:
            n, r = divmod(n, 94)
            code = chr(33 + r) + code
            if not n:
                break
            n -= 1
        ids[pin] = code
    with open(path, "w") as f:
        f.write("$timescale 1ns $end\n$scope module gpio $end\n")
        for pin in ["reset"] + pins:
            f.write(f"$var wire 1 {ids[pin]} {pin} $end\n")
        f.write("$upscope $end\n$enddefinitions $end\n#0\n$dumpvars\n")
        f.write("".join(f"x{ids[p]}\n" for p in pins) + f"0{ids['reset']}\n")
        f.write("$end\n")
        last = 0
        for e in events:
            t = max(e["t"], last)
            if e.get("reset"):
                f.write(f"#{t}\n1{ids['reset']}\n#{t + 1}\n"
                        f"0{ids['reset']}\n")
                last = t + 1
                continue
            value = "z" if e["fn"] == "func" else str(e["lvl"])
            f.write(f"#{t}\n{value}{ids[e['pin']]}\n")
            last = t
    return len(pins)


def cmd_gpio(args, words):
    """Read pins, or drive inputs from outside: GPIO outputs read what
    the camera drives, every other pin what was last driven here (high
    until then); a driven change fires the pin's interrupt if it has
    one. --log, --watch and --vcd read the log of pin changes instead."""
    if args.log or args.watch or args.vcd or args.serve is not None:
        s = pick(args.name, live=False)
        trace = s.path("gpio.jsonl")
        if not os.path.exists(trace):
            die("this session logs no pin changes: its QEMU predates "
                "ingenic-gpio's trace (ingenic-0.6.15)")
        if args.serve is not None:
            from .gpioview import serve
            serve(s, args.serve, pin_table(s.info.get("model")), clean,
                  gpio_pin)
            return 0
        if args.vcd:
            n = gpio_write_vcd(gpio_events(trace, False), args.vcd)
            print(f"{args.vcd}: {n} pins")
            return 0
        try:
            gpio_print_log(gpio_events(trace, args.watch),
                           pin_table(s.info.get("model")))
        except KeyboardInterrupt:
            pass
        return 0
    s = pick(args.name)
    path = "/machine/soc/gpio"
    q = Qmp(s.path("qmp"))
    try:
        props = qom_props(q, path, "in-pa")
        ports = sum(f"in-p{c}" in props for c in "abcdef")

        def get(field, port):
            return q.cmd("qom-get", path=path,
                         property=f"{field}-p{chr(97 + port)}")

        sets = [w for w in words if "=" in w]
        for w in sets:
            name, value = w.split("=", 1)
            port, pin = gpio_pin(name)
            if port >= ports or value not in ("0", "1"):
                die(f"cannot drive {w}")
            level = get("in", port) & ~(1 << pin) | int(value) << pin
            q.cmd("qom-set", path=path, property=f"in-p{chr(97 + port)}",
                  value=level)
        want = {gpio_pin(w.split("=")[0]) for w in words}
        rows = []
        for port in range(ports):
            regs = {f: get(f, port)
                    for f in ("int", "msk", "pat1", "pat0", "pin", "flg")}
            for b in range(32):
                mode = gpio_mode(regs, b)
                if want and (port, b) not in want or not want and \
                        mode.startswith("func") and not args.all:
                    continue
                rows.append(f"P{chr(65 + port)}{b:<3} {port * 32 + b:>3}  "
                            f"{mode:<20} {regs['pin'] >> b & 1}"
                            + ("  flag" if regs["flg"] >> b & 1 else ""))
    finally:
        q.close()
    print("\n".join(rows) if rows else "no GPIO pins configured (--all "
          "lists the pins in device functions too)")
    return 0


def cmd_adc(args, words):
    """Read or set the samples the SADC's channels convert (0-4095), as
    a photoresistor or a battery divider would present them."""
    s = pick(args.name)
    path = "/machine/soc/sadc"
    q = Qmp(s.path("qmp"))
    try:
        qom_props(q, path, "aux0")
        want = []
        for w in words:
            ch, _, value = w.partition("=")
            if not ch.isdigit() or int(ch) > 7 or value and not (
                    value.isdigit() and int(value) < 4096):
                die(f"not a channel (0-7) or a sample (0-4095): {w}")
            if value:
                q.cmd("qom-set", path=path, property=f"aux{ch}",
                      value=int(value))
            want.append(int(ch))
        for ch in want or range(8):
            print(f"{ch} {q.cmd('qom-get', path=path, property=f'aux{ch}')}")
    finally:
        q.close()
    return 0


def cmd_wait(args):
    s = pick(args.name)
    ensure_shell(s, args.timeout)
    print(f"{s.name}: shell")
    return 0


def cmd_console(args):
    import termios
    import tty
    s = pick(args.name)
    if not sys.stdin.isatty():
        die(f"console needs a terminal; without one, `{PROG} sh`, "
            f"`send` and `uboot` do the same")
    start = os.path.getsize(s.log) if args.all else 0
    with s.console(5) as con:
        print(f"{s.name}: attached, Ctrl-] detaches", file=sys.stderr)
        skip = 0
        if args.all:
            # What the log gained while attaching also comes down the
            # console: print the log, then drop that much of the stream
            done = s.log_bytes(0)
            os.write(1, done)
            skip = max(len(done) - start, 0)
        saved = termios.tcgetattr(0)
        tty.setraw(0)
        try:
            while True:
                r = select.select([0, con.fd], [], [])[0]
                if 0 in r:
                    data = os.read(0, 1024)
                    if b"\x1d" in data:
                        break
                    while data:
                        data = data[os.write(con.fd, data):]
                if con.fd in r:
                    try:
                        data = os.read(con.fd, 4096)
                    except OSError:
                        break
                    if not data:
                        break
                    data, skip = data[skip:], max(skip - len(data), 0)
                    os.write(1, data)
        finally:
            termios.tcsetattr(0, termios.TCSADRAIN, saved)
        # Whatever was done by hand, look again before the next command
        s.info["state"] = "unknown"
        s.save()
    print(file=sys.stderr)
    return 0


def cmd_info(args):
    print(describe(pick(args.name, live=False), args.json))
    return 0


def cmd_ls(args):
    found = list(sessions())
    if args.json:
        print("[" + ",\n".join(describe(s, True) for s in found) + "]")
        return 0
    if not found:
        print("no sessions")
    for s in found:
        i = s.info
        ports = i.get("ports") or {}
        state = i.get("state") if s.alive() else "dead"
        net = (f"ssh :{ports['ssh']}  web :{ports['http']}" if i.get("ssh")
               else "no network")
        print(f"{s.name:<24} {state:<8} {i['machine']:<12} {net}")
    return 0


def cmd_down(args):
    for s in list(sessions()) if args.all else [pick(args.name, live=False)]:
        stop(s)
        shutil.rmtree(s.dir, ignore_errors=True)
        print(f"{s.name}: down")
    return 0


def main(argv=None):
    signal.signal(signal.SIGPIPE, signal.SIG_DFL)
    argv = sys.argv[1:] if argv is None else argv
    tail = []
    if "--" in argv:
        i = argv.index("--")
        argv, tail = argv[:i], argv[i + 1:]
    p = argparse.ArgumentParser(
        prog=PROG, description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="command", metavar="COMMAND")
    sub.required = True

    def add(name, text, timeout=None, usage=None, about=None):
        sp = sub.add_parser(name, help=text, usage=usage,
                            description=about or text)
        if timeout:
            sp.add_argument("--timeout", type=int, default=timeout,
                            help=f"seconds (default {timeout})")
        return sp

    sp = add("images", "list built images")
    sp.add_argument("--json", action="store_true")

    sp = add("up", "boot an image", 300,
             "%(prog)s CAMERA|IMAGE [options] [-- QEMU ARGS...]",
             "Boot an image and return at its root shell (about a minute).")
    sp.add_argument("target", help="a camera with a build under output/, "
                    "or the path to an image")
    sp.add_argument("--name", help="session name (default: the camera)")
    sp.add_argument("--uboot", action="store_true",
                    help="stop at the U-Boot prompt")
    sp.add_argument("--no-wait", action="store_true",
                    help="return once QEMU runs; `wait` logs in later")
    sp.add_argument("--console", action="store_true",
                    help="attach this terminal to the console from power-on "
                    "(implies --no-wait)")
    sp.add_argument("--keep", action="store_true",
                    help="boot the session's flash as the last run left it "
                         "instead of a fresh copy of the image")
    sp.add_argument("--soc", help="SoC model, when the image cannot tell "
                    "(t31x, t23n, a1n, ...)")
    sp.add_argument("--machine", help="QEMU machine (default: by SoC)")
    sp.add_argument("--variant", help="soc-variant (default: the model; "
                    "'' for the machine default)")
    sp.add_argument("--ram", type=int, help="RAM in MB")
    sp.add_argument("--qemu", help="qemu-system-mipsel to use (default: "
                    "the pinned one built with the image, or fetched)")
    sp.add_argument("--net", choices=("slirp", "none"), default="slirp")
    sp.add_argument("--fwd", type=int, action="append", default=[],
                    metavar="PORT", help="also forward this guest TCP port")
    sp.add_argument("--sd", metavar="IMAGE", help="an SD card in MSC0 "
                    "(the image is written in place)")
    sp.add_argument("--sd-cd", metavar="PIN", help="the slot's card-detect "
                    "pin, held low with --sd (PB26 or 58; default: gpio."
                    "mmc_cd in the camera's thingino.json; none for no pin)")
    sp.add_argument("--wifi", metavar="SSID:PASS",
                    help="the camera's Wi-Fi chip, with a WPA2 access point "
                    "the camera is set up to join (a reboot the first time)")
    sp.add_argument("--wifi-chip", choices=sorted(set(WIFI_CHIPS.values())),
                    help="the Wi-Fi model, when the image cannot tell")
    sp.add_argument("--portal", action="store_true",
                    help="leave the camera in its setup portal, joined by "
                    "an emulated phone the web forwards go through; --wifi "
                    "then names the network to set it up on")
    sp.add_argument("--password", help="root password (default: the "
                    "build's, else root)")
    sp.add_argument("--json", action="store_true")

    for name, text, timeout, about in (
            ("sh", "run a command on the camera", 120,
             "Run CMD in the camera's /bin/sh over the serial console. "
             "Exits with its status; 124 when --timeout runs out, 255 when "
             "the camera resets under it."),
            ("uboot", "run a U-Boot command", 60,
             "Run CMD at the U-Boot prompt (after up or reboot --uboot) and "
             "exit with its status. 'boot' goes on to Linux and returns at "
             "its shell.")):
        sp = add(name, text, timeout,
                 "%(prog)s [NAME] [--timeout S] -- CMD...", about)
        sp.add_argument("words", nargs="*", metavar="NAME")

    sp = add("put", "copy a file onto the camera", 300,
             "%(prog)s [NAME] LOCAL REMOTE",
             "Copy LOCAL onto the camera; REMOTE may be a directory. SSH "
             "when the image has a wired interface, else the serial "
             "console; checked with md5sum there.")
    sp.add_argument("words", nargs="+", metavar="NAME LOCAL REMOTE")
    sp = add("get", "copy a file off the camera", 300,
             "%(prog)s [NAME] REMOTE LOCAL",
             "Copy REMOTE off the camera; LOCAL may be a directory.")
    sp.add_argument("words", nargs="+", metavar="NAME REMOTE LOCAL")

    sp = add("log", "print the console output")
    sp.add_argument("name", nargs="?", metavar="NAME")
    sp.add_argument("-n", "--lines", type=int, default=100,
                    help="last N lines (default 100, 0 for all)")
    sp.add_argument("--boot", action="store_true",
                    help="all of the current boot")
    sp.add_argument("-f", "--follow", action="store_true")
    sp.add_argument("--raw", action="store_true",
                    help="keep escape sequences and carriage returns")

    sp = add("reboot", "reboot and wait for the shell", 300)
    sp.add_argument("name", nargs="?", metavar="NAME")
    sp.add_argument("--uboot", action="store_true",
                    help="stop at the U-Boot prompt")
    sp.add_argument("--hard", action="store_true",
                    help="reset the machine instead of running reboot")
    sp.add_argument("--no-wait", action="store_true",
                    help="return at once, to watch or type at the boot")

    sp = add("send", "type at the console", 60,
             "%(prog)s [NAME] [--after RE] [--expect RE] [--repeat S] "
             "[--timeout S] -- TEXT",
             "Type TEXT at the console as a person would and print what "
             "the console shows after it. Escapes: \\n Enter, \\r, \\t, "
             "\\e Esc, \\xHH any byte (\\x03 is Ctrl-C), \\\\ a backslash. "
             "Exits 124 when --after or --expect does not show up.")
    sp.add_argument("words", nargs="*", metavar="NAME")
    sp.add_argument("--expect", metavar="REGEX",
                    help="wait for this in what the console shows next")
    sp.add_argument("--after", metavar="REGEX",
                    help="wait for this before typing")
    sp.add_argument("--repeat", type=float, metavar="SECONDS",
                    help="type the text again every SECONDS until --expect")
    sp.add_argument("--raw", action="store_true",
                    help="keep escape sequences and carriage returns")

    sp = add("gpio", "read pins, or drive inputs", None,
             "%(prog)s [NAME] [--all] [PIN[=0|1] ...]",
             "List the pins set up as GPIO (with --all, every pin), show "
             "the PINs named, or drive inputs from outside: PB14=0 pulls "
             "PB14 low, as a pressed button or an inserted card would. "
             "A PIN is PB14 or a Linux GPIO number (46). Columns: pin, "
             "GPIO number, mode, level.")
    sp.add_argument("words", nargs="*", metavar="NAME")
    sp.add_argument("--all", action="store_true",
                    help="also list pins in device functions")
    sp.add_argument("--log", action="store_true",
                    help="every pin change since the session came up")
    sp.add_argument("--watch", action="store_true",
                    help="as --log, then the changes as they happen")
    sp.add_argument("--vcd", metavar="FILE",
                    help="write the pin changes as a VCD waveform")
    sp.add_argument("--serve", nargs="?", type=int, const=0, metavar="PORT",
                    help="serve a live page of the pins on 127.0.0.1 "
                         "(a free port unless PORT)")

    sp = add("adc", "read or set ADC channels", None,
             "%(prog)s [NAME] [CHANNEL[=SAMPLE] ...]",
             "Show the samples the camera's SADC channels convert, or set "
             "them: 0=150 makes channel 0 read 150 of 4095, a dark room "
             "to a photoresistor. Lines: channel, sample.")
    sp.add_argument("words", nargs="*", metavar="NAME")

    sp = add("monitor", "run a QEMU monitor command", None,
             "%(prog)s [NAME] -- COMMAND",
             "Run a QEMU monitor command, such as info registers, set_link "
             "n0 off, system_reset or gdbserver.")
    sp.add_argument("words", nargs="*", metavar="NAME")

    sp = add("wait", "wait until the camera is at a shell", 300)
    sp.add_argument("name", nargs="?", metavar="NAME")
    sp = add("console", "attach this terminal to the console")
    sp.add_argument("name", nargs="?", metavar="NAME")
    sp.add_argument("--all", action="store_true",
                    help="print everything since power-on first")
    sp = add("info", "show a session")
    sp.add_argument("name", nargs="?", metavar="NAME")
    sp.add_argument("--json", action="store_true")
    sp = add("ls", "list sessions")
    sp.add_argument("--json", action="store_true")
    sp = add("down", "stop a session and delete its files")
    sp.add_argument("name", nargs="?", metavar="NAME")
    sp.add_argument("--all", action="store_true")

    args = p.parse_args(argv)
    try:
        if args.command == "up":
            return cmd_up(args, tail)
        if args.command in ("sh", "uboot", "send", "monitor", "gpio",
                            "adc"):
            # [NAME] -- WORDS, or [NAME] 'WORDS'
            words = args.words
            named = words and os.path.exists(Session(words[0]).dir)
            if tail:
                args.name = words[0] if words else None
                cmd = tail
            elif named:
                args.name, cmd = words[0], words[1:]
            else:
                args.name, cmd = None, words
            return globals()[f"cmd_{args.command}"](args, cmd)
        if args.command in ("put", "get"):
            words = args.words
            if len(words) not in (2, 3):
                die(f"usage: {args.command} [NAME] SRC DEST")
            args.name = words[0] if len(words) == 3 else None
            src, dest = words[-2:]
            if args.command == "put":
                args.local, args.remote = src, dest
                return cmd_put(args)
            args.remote, args.local = src, dest
            return cmd_get(args)
        return globals()[f"cmd_{args.command}"](args)
    except KeyboardInterrupt:
        return 130
    except EOFError as e:
        die(str(e), 255)
