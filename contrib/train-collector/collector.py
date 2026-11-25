#!/usr/bin/env python3
"""Thingino training-pool collector.

Accepts opt-in motion frames from cameras running the send2train target and
stores them as a training corpus. Standard library only: it is meant to run as
a small service next to a bucket (or on a box that syncs to one), not as a
framework.

Design constraints, in the order they matter:

  * The camera is not trusted. Every limit the client enforces is enforced
    again here, keyed on a hash of the device's contributor token, on the
    (optionally proxied) client address, and globally.
  * A stored frame must not identify the contributor. The token is hashed
    before it touches the quota table, the client-supplied filename is
    ignored, and every APPn/COM segment (EXIF, GPS, XMP) is dropped from the
    JPEG before it is written. Frames are de-duplicated by content hash so a
    replay does not add a row.
  * Nothing is buffered past the frame limit. Content-Length is required and
    capped, so a slow or lying client cannot exhaust memory.

Endpoint contract (v1):

    POST /v1/samples
      Authorization: Bearer <32 lowercase hex>        (device token)
      X-Thingino-Train: 1
      Content-Type: multipart/form-data; boundary=...
      part "frame" = image/jpeg

    201 {"status":"accepted","id":<16 hex>,"remaining":<int>}
    200 {"status":"duplicate","id":<16 hex>}
    400 malformed request / bad JPEG
    401 missing or malformed token
    405 wrong method
    411 missing Content-Length
    413 frame or request too large
    415 wrong content type / not a JPEG
    429 {"status":"rate_limited","reason":...} + Retry-After
    503 collector at capacity / global cap reached

Configuration is environment only; see README.md.
"""

import hashlib
import hmac
import json
import os
import re
import signal
import ssl
import sys
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

TOKEN_RE = re.compile(r"^[0-9a-f]{32}$")
SCHEMA_VERSION = 1
# Cannot collide with a 16 hex digit unit key, so it can live in the same map.
GLOBAL_KEY = "__global__"
# Tests and foreground debugging can silence the JSON access log.
SILENT = False
SOF_MARKERS = {0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF}


def env_int(name, default):
    raw = os.environ.get(name, "").strip()
    if not raw:
        return default
    try:
        return int(raw)
    except ValueError:
        raise SystemExit(f"{name} must be an integer, got {raw!r}")


class Config:
    def __init__(self):
        self.bind = os.environ.get("TRAIN_BIND", "127.0.0.1:8080")
        self.data_dir = os.environ.get("TRAIN_DATA_DIR", "data")
        self.max_bytes = env_int("TRAIN_MAX_BYTES", 1024 * 1024)
        self.per_unit_day = env_int("TRAIN_PER_UNIT_DAY", 24)
        self.per_unit_interval = env_int("TRAIN_PER_UNIT_INTERVAL", 30)
        self.per_ip_day = env_int("TRAIN_PER_IP_DAY", 96)
        self.global_day = env_int("TRAIN_GLOBAL_DAY", 200000)
        self.min_dimension = env_int("TRAIN_MIN_DIMENSION", 64)
        self.max_dimension = env_int("TRAIN_MAX_DIMENSION", 8192)
        self.inflight_limit = env_int("TRAIN_INFLIGHT_LIMIT", 32)
        self.admin_token = os.environ.get("TRAIN_ADMIN_TOKEN", "")
        # Keyed hash of the client address. Keeping the key out of the data
        # means a leaked spool cannot be turned back into a list of home IPs.
        self.ip_pepper = os.environ.get("TRAIN_IP_PEPPER", "")
        self.trust_proxy = os.environ.get("TRAIN_TRUST_PROXY", "") == "1"
        self.tls_cert = os.environ.get("TRAIN_TLS_CERT", "")
        self.tls_key = os.environ.get("TRAIN_TLS_KEY", "")


class InvalidFrame(Exception):
    pass


def strip_metadata(jpeg):
    """Return (clean_jpeg, width, height), dropping metadata segments.

    APP0 is kept only when it is a plain JFIF header (no JFXX thumbnail);
    every other APPn and every COM segment goes. The entropy-coded scan data
    and the tables are copied verbatim, so the decoded image is unchanged.
    """
    if len(jpeg) < 4 or jpeg[0:2] != b"\xff\xd8":
        raise InvalidFrame("missing JPEG SOI")

    out = bytearray(b"\xff\xd8")
    i = 2
    width = height = 0
    seen_sof = False

    while i < len(jpeg):
        if jpeg[i] != 0xFF:
            raise InvalidFrame("corrupt marker stream")
        while i < len(jpeg) and jpeg[i] == 0xFF:
            i += 1
        if i >= len(jpeg):
            raise InvalidFrame("truncated marker")
        marker = jpeg[i]
        i += 1

        if marker == 0xD9:  # EOI before any scan: well-formed but useless
            raise InvalidFrame("no image scan")

        if marker == 0xDA:  # SOS: copy scan data through the last EOI
            if not seen_sof:
                raise InvalidFrame("scan before frame header")
            end = jpeg.rfind(b"\xff\xd9")
            if end < i:
                raise InvalidFrame("missing EOI")
            out += jpeg[i - 2 : end + 2]
            return bytes(out), width, height

        # Standalone markers: RSTn and TEM carry no length field.
        if 0xD0 <= marker <= 0xD7 or marker == 0x01:
            out += bytes((0xFF, marker))
            continue

        if i + 2 > len(jpeg):
            raise InvalidFrame("truncated segment")
        seglen = int.from_bytes(jpeg[i : i + 2], "big")
        if seglen < 2 or i + seglen > len(jpeg):
            raise InvalidFrame("bad segment length")
        seg = jpeg[i + 2 : i + seglen]

        keep = True
        if 0xE0 <= marker <= 0xEF:
            keep = marker == 0xE0 and seg[:5] == b"JFIF\x00"
        elif marker == 0xFE:
            keep = False

        if marker in SOF_MARKERS:
            if len(seg) < 5:
                raise InvalidFrame("short frame header")
            height = int.from_bytes(seg[1:3], "big")
            width = int.from_bytes(seg[3:5], "big")
            seen_sof = True

        if keep:
            out += bytes((0xFF, marker)) + jpeg[i : i + seglen]
        i += seglen

    raise InvalidFrame("truncated JPEG")


def parse_multipart(body, boundary):
    """Return the payload of the part named "frame", or None."""
    delimiter = b"--" + boundary
    for chunk in body.split(delimiter)[1:]:
        if chunk.startswith(b"--"):
            break
        if not chunk.startswith(b"\r\n"):
            continue
        chunk = chunk[2:]
        if chunk.endswith(b"\r\n"):
            chunk = chunk[:-2]
        if b"\r\n\r\n" not in chunk:
            continue
        head, payload = chunk.split(b"\r\n\r\n", 1)
        headers = {}
        for line in head.split(b"\r\n"):
            if b":" in line:
                key, value = line.split(b":", 1)
                headers[key.strip().lower()] = value.strip()
        disposition = headers.get(b"content-disposition", b"").lower()
        if b'name="frame"' in disposition:
            return payload
    return None


def content_type_params(value):
    parts = value.split(";")
    base = parts[0].strip().lower()
    params = {}
    for part in parts[1:]:
        if "=" not in part:
            continue
        key, val = part.split("=", 1)
        params[key.strip().lower()] = val.strip().strip('"')
    return base, params


class DayCounter:
    """Per-key daily counters that survive a restart.

    Counts are kept in memory and flushed to a small JSON file at most once a
    second. A crash can lose the last second of counting; that is acceptable
    for a defence-in-depth limit and much cheaper than fsyncing every upload.
    """

    def __init__(self, path, flush_interval=1.0):
        self.path = path
        self.flush_interval = flush_interval
        self.lock = threading.Lock()
        self.day = time.strftime("%Y-%m-%d", time.gmtime())
        self.counts = {}
        self.dirty = False
        self.last_flush = 0.0
        self._load()

    def _load(self):
        try:
            with open(self.path, "r", encoding="utf-8") as handle:
                stored = json.load(handle)
        except (OSError, ValueError):
            return
        if stored.get("day") == self.day and isinstance(stored.get("counts"), dict):
            self.counts = {str(k): int(v) for k, v in stored["counts"].items()}

    def _roll(self):
        today = time.strftime("%Y-%m-%d", time.gmtime())
        if today != self.day:
            self.day = today
            self.counts = {}
            self.dirty = True

    def get(self, key):
        with self.lock:
            self._roll()
            return self.counts.get(key, 0)

    def total(self):
        with self.lock:
            self._roll()
            return self.counts.get(GLOBAL_KEY, 0)

    def bump(self, key):
        with self.lock:
            self._roll()
            value = self.counts.get(key, 0) + 1
            self.counts[key] = value
            self.dirty = True
            self._maybe_flush()
            return value

    def _maybe_flush(self):
        now = time.monotonic()
        if not self.dirty or now - self.last_flush < self.flush_interval:
            return
        self._flush_locked()

    def _flush_locked(self):
        self.last_flush = time.monotonic()
        if not self.dirty:
            return
        tmp = f"{self.path}.{os.getpid()}.tmp"
        try:
            os.makedirs(os.path.dirname(self.path), exist_ok=True)
            with open(tmp, "w", encoding="utf-8") as handle:
                json.dump({"day": self.day, "counts": self.counts}, handle)
            os.replace(tmp, self.path)
            self.dirty = False
        except OSError as exc:
            log({"event": "quota_flush_failed", "error": str(exc)})

    def flush(self):
        with self.lock:
            self._flush_locked()


class Collector:
    def __init__(self, config):
        self.config = config
        self.root = os.path.abspath(config.data_dir)
        self.spool = os.path.join(self.root, "frames")
        self.tmp = os.path.join(self.root, "_tmp")
        self.index = os.path.join(self.root, "index")
        self.meta = os.path.join(self.root, "_state")
        for path in (self.spool, self.tmp, self.index, self.meta):
            os.makedirs(path, exist_ok=True)
        self.counter = DayCounter(os.path.join(self.meta, "quota.json"))
        self.ip_lock = threading.Lock()
        self.ip_counts = {}
        self.unit_last = {}
        self.inflight = threading.BoundedSemaphore(config.inflight_limit)
        self.ip_pepper = config.ip_pepper.encode() or os.urandom(32)

    # -- identity ---------------------------------------------------------

    def ip_key(self, address):
        return hmac.new(self.ip_pepper, address.encode(), hashlib.sha256).hexdigest()[:24]

    @staticmethod
    def unit_key(token):
        return hashlib.sha256(token.encode()).hexdigest()[:16]

    # -- limits -----------------------------------------------------------

    def ip_day(self, ip_key):
        with self.ip_lock:
            day = time.strftime("%Y-%m-%d", time.gmtime())
            entry = self.ip_counts.get(ip_key)
            if entry is None or entry[0] != day:
                entry = (day, 0)
                self.ip_counts[ip_key] = entry
            return entry[1]

    def bump_ip(self, ip_key):
        with self.ip_lock:
            day = time.strftime("%Y-%m-%d", time.gmtime())
            entry = self.ip_counts.get(ip_key)
            count = 1 if entry is None or entry[0] != day else entry[1] + 1
            self.ip_counts[ip_key] = (day, count)
            # Keep the map bounded on a busy day.
            if len(self.ip_counts) > 65536:
                self.ip_counts = {ip_key: (day, count)}

    def unit_last_seen(self, unit):
        with self.ip_lock:
            return self.unit_last.get(unit, 0.0)

    def note_unit(self, unit, when):
        with self.ip_lock:
            self.unit_last[unit] = when
            if len(self.unit_last) > 65536:
                self.unit_last = {unit: when}

    # -- storage ----------------------------------------------------------

    def already_seen(self, digest):
        return os.path.exists(os.path.join(self.index, digest[:2], digest))

    def remember(self, digest):
        directory = os.path.join(self.index, digest[:2])
        os.makedirs(directory, exist_ok=True)
        path = os.path.join(directory, digest)
        try:
            with open(path, "xb"):
                pass
        except FileExistsError:
            pass

    def store(self, clean, digest, meta):
        day_dir = os.path.join(self.spool, time.strftime("%Y/%m/%d", time.gmtime()))
        os.makedirs(day_dir, exist_ok=True)
        final = os.path.join(day_dir, digest + ".jpg")
        if os.path.exists(final):
            return False
        tmp = os.path.join(self.tmp, uuid.uuid4().hex)
        try:
            with open(tmp, "xb") as handle:
                handle.write(clean)
                handle.flush()
                os.fsync(handle.fileno())
            os.replace(tmp, final)
        finally:
            if os.path.exists(tmp):
                os.unlink(tmp)
        with open(final[:-4] + ".json", "w", encoding="utf-8") as handle:
            json.dump(meta, handle, sort_keys=True)
        return True


def log(record):
    if SILENT:
        return
    sys.stderr.write(json.dumps(record, sort_keys=True) + "\n")
    sys.stderr.flush()


class Handler(BaseHTTPRequestHandler):
    server_version = "thingino-train/1"
    sys_version = ""
    protocol_version = "HTTP/1.1"
    timeout = 30
    collector = None  # set by main()

    # -- plumbing ---------------------------------------------------------

    def log_message(self, fmt, *args):
        # Requests are logged as one JSON object each, not as access-log lines.
        return

    def address_string(self):
        if self.collector.config.trust_proxy:
            forwarded = self.headers.get("X-Forwarded-For", "")
            if forwarded:
                return forwarded.split(",")[0].strip()
        return self.client_address[0]

    def send_json(self, status, payload, headers=None):
        body = json.dumps(payload, sort_keys=True).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        for key, value in (headers or {}).items():
            self.send_header(key, value)
        self.end_headers()
        self.wfile.write(body)

    def error(self, status, code, message, headers=None):
        self.send_json(status, {"error": {"code": code, "message": message}}, headers)

    # -- routing ----------------------------------------------------------

    def do_GET(self):
        if self.path == "/healthz":
            self.send_json(200, {"status": "ok"})
            return
        if self.path == "/v1/stats":
            self.handle_stats()
            return
        self.error(404, "not_found", "unknown path")

    def do_POST(self):
        if self.path != "/v1/samples":
            self.error(404, "not_found", "unknown path")
            return
        self.handle_upload()

    def do_PUT(self):
        self.error(405, "method_not_allowed", "method not allowed")

    do_DELETE = do_PATCH = do_PUT

    # -- handlers ---------------------------------------------------------

    def handle_stats(self):
        config = self.collector.config
        token = self.bearer()
        if not config.admin_token or not hmac.compare_digest(token, config.admin_token):
            self.error(401, "unauthorized", "admin token required")
            return
        self.send_json(
            200,
            {
                "day": self.collector.counter.day,
                "accepted_today": self.collector.counter.total(),
                "global_day_limit": config.global_day,
            },
        )

    def bearer(self):
        header = self.headers.get("Authorization", "")
        if header.lower().startswith("bearer "):
            return header[7:].strip()
        return self.headers.get("X-Thingino-Token", "").strip()

    def handle_upload(self):
        collector = self.collector
        config = collector.config

        if not collector.inflight.acquire(blocking=False):
            self.error(503, "busy", "collector at capacity", {"Retry-After": "30"})
            return
        try:
            self._handle_upload(collector, config)
        finally:
            collector.inflight.release()

    def _handle_upload(self, collector, config):
        if self.headers.get("Transfer-Encoding"):
            self.error(411, "length_required", "Content-Length is required")
            return

        token = self.bearer()
        if not TOKEN_RE.match(token):
            self.error(401, "bad_token", "expected a 32 character hex token")
            return

        if self.headers.get("X-Thingino-Train", "") != "1":
            self.error(400, "bad_schema", "X-Thingino-Train: 1 is required")
            return

        base_type, params = content_type_params(self.headers.get("Content-Type", ""))
        if base_type != "multipart/form-data":
            self.error(415, "bad_content_type", "multipart/form-data is required")
            return
        boundary = params.get("boundary", "")
        if not boundary or len(boundary) > 70:
            self.error(400, "bad_content_type", "missing multipart boundary")
            return

        try:
            length = int(self.headers.get("Content-Length", ""))
        except ValueError:
            self.error(411, "length_required", "Content-Length is required")
            return
        # Multipart framing overhead on top of the frame itself.
        hard_limit = config.max_bytes + 8192
        if length <= 0:
            self.error(400, "empty", "empty request body")
            return
        if length > hard_limit:
            self.error(413, "too_large", "request exceeds the frame limit")
            return

        body = self.rfile.read(length)
        if len(body) != length:
            self.error(400, "truncated", "short request body")
            return

        payload = parse_multipart(body, boundary.encode())
        if payload is None:
            self.error(400, "no_frame", 'multipart part "frame" is required')
            return
        if not payload:
            self.error(400, "empty", "empty frame")
            return
        if len(payload) > config.max_bytes:
            self.error(413, "too_large", "frame exceeds the size limit")
            return

        try:
            clean, width, height = strip_metadata(payload)
        except InvalidFrame as exc:
            self.error(415, "bad_jpeg", str(exc))
            return

        if width < config.min_dimension or height < config.min_dimension:
            self.error(
                415,
                "too_small",
                f"frame {width}x{height} is below the {config.min_dimension}px minimum",
            )
            return
        if width > config.max_dimension or height > config.max_dimension:
            self.error(415, "too_large", "frame dimensions out of range")
            return

        digest = hashlib.sha256(clean).hexdigest()
        unit = collector.unit_key(token)
        ip_key = collector.ip_key(self.address_string())
        now = time.time()

        # A frame that is already in the corpus is answered as a duplicate
        # before any quota is spent: a replay must not cost the contributor
        # one of their daily frames.
        if collector.already_seen(digest):
            self.send_json(200, {"status": "duplicate", "id": digest[:16]})
            log({"event": "duplicate", "unit": unit, "sha256": digest})
            return

        if collector.counter.total() >= config.global_day:
            self.error(503, "pool_full", "daily collection limit reached", {"Retry-After": "3600"})
            return

        unit_day = collector.counter.get(unit)
        if unit_day >= config.per_unit_day:
            self.error(
                429,
                "unit_quota",
                f"contributor limit of {config.per_unit_day} frames/day reached",
                {"Retry-After": "3600"},
            )
            return

        last_seen = collector.unit_last_seen(unit)
        if last_seen and now - last_seen < config.per_unit_interval:
            wait = int(config.per_unit_interval - (now - last_seen)) + 1
            self.error(429, "unit_interval", "uploads too close together", {"Retry-After": str(wait)})
            return

        if collector.ip_day(ip_key) >= config.per_ip_day:
            self.error(429, "ip_quota", "client address limit reached", {"Retry-After": "3600"})
            return

        meta = {
            "schema": SCHEMA_VERSION,
            "sha256": digest,
            "received_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(now)),
            "bytes": len(clean),
            "width": width,
            "height": height,
            "unit": unit,
            "source": ip_key,
        }
        if not collector.store(clean, digest, meta):
            self.send_json(200, {"status": "duplicate", "id": digest[:16]})
            return

        collector.remember(digest)
        collector.counter.bump(GLOBAL_KEY)
        count = collector.counter.bump(unit)
        collector.bump_ip(ip_key)
        collector.note_unit(unit, now)

        self.send_json(
            201,
            {
                "status": "accepted",
                "id": digest[:16],
                "remaining": max(0, config.per_unit_day - count),
            },
        )
        log(
            {
                "event": "accepted",
                "unit": unit,
                "sha256": digest,
                "bytes": len(clean),
                "width": width,
                "height": height,
                "unit_day": count,
            }
        )


class Server(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True
    request_queue_size = 64

    def server_bind(self):
        super().server_bind()


def main():
    config = Config()
    if os.environ.get("TRAIN_LOG_SILENT", "") == "1":
        global SILENT
        SILENT = True
    collector = Collector(config)
    Handler.collector = collector

    host, _, port = config.bind.rpartition(":")
    server = Server((host or "0.0.0.0", int(port)), Handler)

    # Tests (and supervisors that cannot parse the log) read the bound port
    # from here; it is only written when asked for.
    port_file = os.environ.get("TRAIN_PORT_FILE", "")
    if port_file:
        with open(port_file, "w", encoding="utf-8") as handle:
            handle.write(str(server.server_address[1]))

    if config.tls_cert and config.tls_key:
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.minimum_version = ssl.TLSVersion.TLSv1_2
        context.load_cert_chain(config.tls_cert, config.tls_key)
        server.socket = context.wrap_socket(server.socket, server_side=True)

    # Somebody has to shove the daily counters to disk on a clean stop.
    def stop(_signum, _frame):
        collector.counter.flush()
        raise KeyboardInterrupt

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)

    log(
        {
            "event": "listening",
            "bind": config.bind,
            "port": server.server_address[1],
            "data_dir": collector.root,
            "tls": bool(config.tls_cert),
            "per_unit_day": config.per_unit_day,
            "per_ip_day": config.per_ip_day,
            "global_day": config.global_day,
        }
    )
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        collector.counter.flush()
        server.server_close()


if __name__ == "__main__":
    main()
