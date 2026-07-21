import hashlib
import sys
import unittest
from pathlib import Path
from tempfile import NamedTemporaryFile
from types import SimpleNamespace

SCRIPT_DIR = Path(__file__).resolve().parents[1]
REPO_ROOT = SCRIPT_DIR.parents[1]
sys.path.insert(0, str(SCRIPT_DIR))

from t31_spl_extract import slice_spl  # noqa: E402
from t31_spl_forge import build_native_helper, find_nonce_native, find_nonce_python  # noqa: E402
from t31_spl_utils import select_verification_result, swap_bytes_per_word  # noqa: E402


class TestT31SplTools(unittest.TestCase):
    def test_swap_bytes_per_word(self):
        self.assertEqual(swap_bytes_per_word(bytes.fromhex("11223344aabbccdd")), bytes.fromhex("44332211ddccbbaa"))

    def test_verify_workspace_stock_sample(self):
        sample = REPO_ROOT / "wyze-video-doorbellv2.bin"
        if not sample.exists():
            self.skipTest(f"sample image not found: {sample}")
        image = sample.read_bytes()[:0x4B80]
        result = select_verification_result(image)
        self.assertTrue(result.matches)
        self.assertEqual(result.exponent, 65537)
        self.assertEqual(result.target_word, 0x3024CC99)

    def test_verify_workspace_spl_sample(self):
        sample = REPO_ROOT / "spl.bin"
        if not sample.exists():
            self.skipTest(f"sample image not found: {sample}")
        image = sample.read_bytes()[:0x4B80]
        result = select_verification_result(image)
        self.assertTrue(result.matches)
        self.assertEqual(result.exponent, 65537)
        self.assertEqual(result.target_word, 0x71A5F2CE)

    def test_slice_spl(self):
        firmware = b"A" * 0x40 + b"B" * 0x100 + b"C" * 0x40
        self.assertEqual(slice_spl(firmware, 0x40, 0x100), b"B" * 0x100)

    def test_find_nonce_python_toy_payload(self):
        payload = bytearray(b"A" * 128)
        nonce_offset = 12
        expected_nonce = 0x1234
        payload[nonce_offset : nonce_offset + 4] = expected_nonce.to_bytes(4, "little")
        target_prefix = hashlib.sha256(payload).digest()[:4]
        payload[nonce_offset : nonce_offset + 4] = (0).to_bytes(4, "little")
        args = SimpleNamespace(workers=1, nonce_start=0, nonce_limit=0x20000, nonce_byteorder="little")
        self.assertEqual(find_nonce_python(bytes(payload), target_prefix, nonce_offset, args), expected_nonce)

    def test_find_nonce_native_toy_payload(self):
        helper = build_native_helper()
        if helper is None:
            self.skipTest("native helper could not be compiled")

        payload_offset = 0x800
        payload = bytearray(b"B" * 128)
        nonce_offset = 20
        expected_nonce = 0x4321
        payload[nonce_offset : nonce_offset + 4] = expected_nonce.to_bytes(4, "little")
        target_word = int.from_bytes(hashlib.sha256(payload).digest()[:4], "big")
        payload[nonce_offset : nonce_offset + 4] = (0).to_bytes(4, "little")
        image = bytes(payload_offset) + bytes(payload)
        args = SimpleNamespace(workers=2, nonce_start=0, nonce_limit=0x10000, nonce_byteorder="little")

        with NamedTemporaryFile(delete=True) as tmp:
            Path(tmp.name).write_bytes(image)
            found = find_nonce_native(
                Path(tmp.name),
                payload_offset,
                payload_offset + len(payload),
                target_word,
                nonce_offset,
                args,
            )
        self.assertEqual(found, expected_nonce)


if __name__ == "__main__":
    unittest.main()
