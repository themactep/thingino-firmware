#!/usr/bin/env python3
"""Unit tests for the Thingino training-pool collector.

Run from this directory:

    python3 -m unittest -v test_collector.py

The collector is started in-process on an ephemeral port with a throwaway data
directory, so the tests need no network and no services.
"""

import base64
import hashlib
import http.client
import json
import os
import shutil
import tempfile
import threading
import unittest

import collector

# 1x1 JFIF JPEG: small enough to inline, complete enough to parse.
TINY_JPEG = base64.b64decode(
    "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRof"
    "Hh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/wAALCAABAAEBAREA/8QAFAAB"
    "AAAAAAAAAAAAAAAAAAAAAP/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8Af//Z"
)

TOKEN = "0123456789abcdef0123456789abcdef"
ADMIN = "admin-secret"
EXIF_PAYLOAD = b"Exif\x00\x00MM\x00*\x00\x00\x00\x08" + b"\x00" * 32


def jpeg_with_metadata(base=TINY_JPEG):
    """Return base plus an EXIF APP1 segment and a COM segment."""
    comment = b"camera-here"
    app1 = b"\xff\xe1" + (len(EXIF_PAYLOAD) + 2).to_bytes(2, "big") + EXIF_PAYLOAD
    com = b"\xff\xfe" + (len(comment) + 2).to_bytes(2, "big") + comment
    return base[:2] + app1 + com + base[2:]


def variant(index):
    """A distinct, well-formed frame: same image, different SOF height."""
    marker = TINY_JPEG.index(b"\xff\xc0")
    data = bytearray(TINY_JPEG)
    data[marker + 6] = index + 1
    return bytes(data)


def multipart(frame, boundary="thingino-test-boundary"):
    return (
        f"--{boundary}\r\n"
        'Content-Disposition: form-data; name="frame"; filename="frame.jpg"\r\n'
        "Content-Type: image/jpeg\r\n\r\n"
    ).encode() + frame + f"\r\n--{boundary}--\r\n".encode(), boundary


class CollectorHarness(unittest.TestCase):
    """Collector on an ephemeral port, with a throwaway data directory."""

    env = {}

    def setUp(self):
        collector.SILENT = True
        self.data_dir = tempfile.mkdtemp(prefix="train-collector-test.")
        enabled = {
            "TRAIN_BIND": "127.0.0.1:0",
            "TRAIN_DATA_DIR": self.data_dir,
            "TRAIN_PER_UNIT_DAY": "3",
            "TRAIN_PER_UNIT_INTERVAL": "0",
            "TRAIN_PER_IP_DAY": "100",
            "TRAIN_GLOBAL_DAY": "1000",
            "TRAIN_MIN_DIMENSION": "1",
            "TRAIN_MAX_BYTES": "65536",
            "TRAIN_ADMIN_TOKEN": ADMIN,
            "TRAIN_IP_PEPPER": "test-pepper",
        }
        enabled.update(self.env)
        self._saved_env = {key: os.environ.get(key) for key in enabled}
        os.environ.update(enabled)

        config = collector.Config()
        self.collector = collector.Collector(config)
        collector.Handler.collector = self.collector
        self.server = collector.Server(("127.0.0.1", 0), collector.Handler)
        self.port = self.server.server_address[1]
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=5)
        for key, value in self._saved_env.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value
        shutil.rmtree(self.data_dir, ignore_errors=True)

    # -- helpers ----------------------------------------------------------

    def request(self, method="POST", path="/v1/samples", body=b"", headers=None):
        conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=10)
        try:
            conn.request(method, path, body=body, headers=headers or {})
            response = conn.getresponse()
            return response, response.read()
        finally:
            conn.close()

    def upload(self, frame=None, token=TOKEN, extra_headers=None):
        body, boundary = multipart(frame if frame is not None else TINY_JPEG)
        headers = {
            "Content-Type": f"multipart/form-data; boundary={boundary}",
            "Content-Length": str(len(body)),
            "Authorization": f"Bearer {token}",
            "X-Thingino-Train": "1",
        }
        headers.update(extra_headers or {})
        return self.request(body=body, headers=headers)

    def stored_frames(self):
        found = []
        for root, _dirs, files in os.walk(os.path.join(self.data_dir, "frames")):
            found.extend(os.path.join(root, name) for name in files if name.endswith(".jpg"))
        return sorted(found)


class CollectorCase(CollectorHarness):
    """Behaviour every deployment must have."""

    def test_healthz(self):
        response, payload = self.request("GET", "/healthz")
        self.assertEqual(response.status, 200)
        self.assertEqual(json.loads(payload), {"status": "ok"})

    def test_accepts_frame_and_strips_metadata(self):
        response, payload = self.upload(jpeg_with_metadata())
        self.assertEqual(response.status, 201, payload)
        body = json.loads(payload)
        self.assertEqual(body["status"], "accepted")
        self.assertIn("remaining", body)
        self.assertEqual(response.getheader("X-Content-Type-Options"), "nosniff")

        frames = self.stored_frames()
        self.assertEqual(len(frames), 1)
        with open(frames[0], "rb") as handle:
            stored = handle.read()
        self.assertNotIn(b"Exif", stored)
        self.assertNotIn(b"camera-here", stored)
        self.assertTrue(stored.startswith(b"\xff\xd8"))
        self.assertTrue(stored.endswith(b"\xff\xd9"))

        with open(frames[0][:-4] + ".json", encoding="utf-8") as handle:
            sidecar = json.load(handle)
        self.assertEqual(sidecar["width"], 1)
        self.assertEqual(sidecar["height"], 1)
        self.assertEqual(sidecar["sha256"], hashlib.sha256(stored).hexdigest())
        # Neither the token nor the raw client address may be recoverable
        # from what is stored on disk.
        serialized = json.dumps(sidecar)
        self.assertNotIn(TOKEN, serialized)
        self.assertNotIn("127.0.0.1", serialized)

    def test_plain_jpeg_is_byte_identical(self):
        response, _payload = self.upload(TINY_JPEG)
        self.assertEqual(response.status, 201)
        with open(self.stored_frames()[0], "rb") as handle:
            self.assertEqual(handle.read(), TINY_JPEG)

    def test_duplicate_is_not_stored_twice(self):
        first, _ = self.upload()
        second, payload = self.upload()
        self.assertEqual(first.status, 201)
        self.assertEqual(second.status, 200)
        self.assertEqual(json.loads(payload)["status"], "duplicate")
        self.assertEqual(len(self.stored_frames()), 1)

    def test_missing_token_is_rejected(self):
        body, boundary = multipart(TINY_JPEG)
        response, _ = self.request(
            body=body,
            headers={
                "Content-Type": f"multipart/form-data; boundary={boundary}",
                "Content-Length": str(len(body)),
                "X-Thingino-Train": "1",
            },
        )
        self.assertEqual(response.status, 401)

    def test_bad_token_shape_is_rejected(self):
        response, _ = self.upload(token="not-a-token")
        self.assertEqual(response.status, 401)
        self.assertEqual(self.stored_frames(), [])

    def test_schema_header_is_required(self):
        response, _ = self.upload(extra_headers={"X-Thingino-Train": "2"})
        self.assertEqual(response.status, 400)

    def test_wrong_content_type(self):
        response, _ = self.request(
            body=TINY_JPEG,
            headers={
                "Content-Type": "image/jpeg",
                "Content-Length": str(len(TINY_JPEG)),
                "Authorization": f"Bearer {TOKEN}",
                "X-Thingino-Train": "1",
            },
        )
        self.assertEqual(response.status, 415)

    def test_missing_content_length(self):
        body, boundary = multipart(TINY_JPEG)
        response, _ = self.request(
            body=body,
            headers={
                "Content-Type": f"multipart/form-data; boundary={boundary}",
                "Content-Length": "",
                "Authorization": f"Bearer {TOKEN}",
                "X-Thingino-Train": "1",
            },
        )
        self.assertIn(response.status, (400, 411))

    def test_non_jpeg_is_rejected(self):
        response, _ = self.upload(b"<html>not a frame</html>")
        self.assertEqual(response.status, 415)

    def test_truncated_jpeg_is_rejected(self):
        response, _ = self.upload(TINY_JPEG[:40])
        self.assertEqual(response.status, 415)

    def test_oversized_frame_is_rejected(self):
        response, _ = self.upload(TINY_JPEG + b"\x00" * 70000)
        self.assertEqual(response.status, 413)

    def test_unit_daily_quota(self):
        for index in range(3):
            response, _ = self.upload(variant(index))
            self.assertEqual(response.status, 201, f"frame {index}")
        response, payload = self.upload(variant(9))
        self.assertEqual(response.status, 429)
        self.assertEqual(json.loads(payload)["error"]["code"], "unit_quota")
        self.assertEqual(response.getheader("Retry-After"), "3600")

    def test_method_not_allowed(self):
        response, _ = self.request("PUT", body=b"x", headers={"Content-Length": "1"})
        self.assertEqual(response.status, 405)

    def test_unknown_path(self):
        response, _ = self.request("GET", "/v1/nope")
        self.assertEqual(response.status, 404)

    def test_stats_requires_admin(self):
        response, _ = self.request("GET", "/v1/stats")
        self.assertEqual(response.status, 401)
        response, payload = self.request(
            "GET", "/v1/stats", headers={"Authorization": f"Bearer {ADMIN}"}
        )
        self.assertEqual(response.status, 200)
        self.assertEqual(json.loads(payload)["global_day_limit"], 1000)


class IntervalCase(CollectorHarness):
    env = {"TRAIN_PER_UNIT_INTERVAL": "60", "TRAIN_PER_UNIT_DAY": "50"}

    def test_second_upload_is_throttled(self):
        first, _ = self.upload()
        self.assertEqual(first.status, 201)
        response, payload = self.upload(variant(1))
        self.assertEqual(response.status, 429)
        self.assertEqual(json.loads(payload)["error"]["code"], "unit_interval")
        self.assertGreaterEqual(int(response.getheader("Retry-After")), 1)


class IpQuotaCase(CollectorHarness):
    env = {"TRAIN_PER_IP_DAY": "1", "TRAIN_PER_UNIT_DAY": "50"}

    def test_ip_quota(self):
        first, _ = self.upload()
        self.assertEqual(first.status, 201)
        response, payload = self.upload(variant(1), token="fedcba9876543210fedcba9876543210")
        self.assertEqual(response.status, 429)
        self.assertEqual(json.loads(payload)["error"]["code"], "ip_quota")


class MinDimensionCase(CollectorHarness):
    env = {"TRAIN_MIN_DIMENSION": "64"}

    def test_small_frame_is_rejected(self):
        response, payload = self.upload()
        self.assertEqual(response.status, 415)
        self.assertEqual(json.loads(payload)["error"]["code"], "too_small")


class GlobalCapCase(CollectorHarness):
    env = {"TRAIN_GLOBAL_DAY": "1", "TRAIN_PER_UNIT_DAY": "50"}

    def test_global_cap(self):
        first, _ = self.upload()
        self.assertEqual(first.status, 201)
        response, payload = self.upload(variant(1), token="fedcba9876543210fedcba9876543210")
        self.assertEqual(response.status, 503)
        self.assertEqual(json.loads(payload)["error"]["code"], "pool_full")


if __name__ == "__main__":
    unittest.main()
