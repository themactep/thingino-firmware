#!/usr/bin/env python3

from __future__ import annotations

import hashlib
from dataclasses import dataclass

DEFAULT_SIG_OFFSET = 0x200
DEFAULT_KEY_OFFSET = 0x300
DEFAULT_PAYLOAD_OFFSET = 0x800
DEFAULT_HASH_END_FIELD_OFFSET = 0x0C
SUPPORTED_EXPONENTS = (65537, 3)

SKIP_SIZE = 2048
CRC_POSITION = 9

CRC7_SYNDROME_TABLE = [
    0x00, 0x09, 0x12, 0x1b, 0x24, 0x2d, 0x36, 0x3f,
    0x48, 0x41, 0x5a, 0x53, 0x6c, 0x65, 0x7e, 0x77,
    0x19, 0x10, 0x0b, 0x02, 0x3d, 0x34, 0x2f, 0x26,
    0x51, 0x58, 0x43, 0x4a, 0x75, 0x7c, 0x67, 0x6e,
    0x32, 0x3b, 0x20, 0x29, 0x16, 0x1f, 0x04, 0x0d,
    0x7a, 0x73, 0x68, 0x61, 0x5e, 0x57, 0x4c, 0x45,
    0x2b, 0x22, 0x39, 0x30, 0x0f, 0x06, 0x1d, 0x14,
    0x63, 0x6a, 0x71, 0x78, 0x47, 0x4e, 0x55, 0x5c,
    0x64, 0x6d, 0x76, 0x7f, 0x40, 0x49, 0x52, 0x5b,
    0x2c, 0x25, 0x3e, 0x37, 0x08, 0x01, 0x1a, 0x13,
    0x7d, 0x74, 0x6f, 0x66, 0x59, 0x50, 0x4b, 0x42,
    0x35, 0x3c, 0x27, 0x2e, 0x11, 0x18, 0x03, 0x0a,
    0x56, 0x5f, 0x44, 0x4d, 0x72, 0x7b, 0x60, 0x69,
    0x1e, 0x17, 0x0c, 0x05, 0x3a, 0x33, 0x28, 0x21,
    0x4f, 0x46, 0x5d, 0x54, 0x6b, 0x62, 0x79, 0x70,
    0x07, 0x0e, 0x15, 0x1c, 0x23, 0x2a, 0x31, 0x38,
    0x41, 0x48, 0x53, 0x5a, 0x65, 0x6c, 0x77, 0x7e,
    0x09, 0x00, 0x1b, 0x12, 0x2d, 0x24, 0x3f, 0x36,
    0x58, 0x51, 0x4a, 0x43, 0x7c, 0x75, 0x6e, 0x67,
    0x10, 0x19, 0x02, 0x0b, 0x34, 0x3d, 0x26, 0x2f,
    0x73, 0x7a, 0x61, 0x68, 0x57, 0x5e, 0x45, 0x4c,
    0x3b, 0x32, 0x29, 0x20, 0x1f, 0x16, 0x0d, 0x04,
    0x6a, 0x63, 0x78, 0x71, 0x4e, 0x47, 0x5c, 0x55,
    0x22, 0x2b, 0x30, 0x39, 0x06, 0x0f, 0x14, 0x1d,
    0x25, 0x2c, 0x37, 0x3e, 0x01, 0x08, 0x13, 0x1a,
    0x6d, 0x64, 0x7f, 0x76, 0x49, 0x40, 0x5b, 0x52,
    0x3c, 0x35, 0x2e, 0x27, 0x18, 0x11, 0x0a, 0x03,
    0x74, 0x7d, 0x66, 0x6f, 0x50, 0x59, 0x42, 0x4b,
    0x17, 0x1e, 0x05, 0x0c, 0x33, 0x3a, 0x21, 0x28,
    0x5f, 0x56, 0x4d, 0x44, 0x7b, 0x72, 0x69, 0x60,
    0x0e, 0x07, 0x1c, 0x15, 0x2a, 0x23, 0x38, 0x31,
    0x46, 0x4f, 0x54, 0x5d, 0x62, 0x6b, 0x70, 0x79,
]


def parse_int(value: str) -> int:
    return int(value, 0)


def swap_bytes_per_word(data: bytes) -> bytes:
    if len(data) % 4 != 0:
        raise ValueError(f"data length must be word-aligned, got {len(data)}")
    return b"".join(data[i : i + 4][::-1] for i in range(0, len(data), 4))


def read_u32_le(blob: bytes, offset: int) -> int:
    end = offset + 4
    if end > len(blob):
        raise ValueError(f"cannot read u32 at 0x{offset:x} from {len(blob)}-byte blob")
    return int.from_bytes(blob[offset:end], "little")


def resolve_hash_end(image: bytes, hash_end: int | None, field_offset: int) -> int:
    if hash_end is not None:
        if hash_end <= DEFAULT_PAYLOAD_OFFSET or hash_end > len(image):
            raise ValueError(f"hash end 0x{hash_end:x} is outside the image")
        return hash_end

    candidate = read_u32_le(image, field_offset)
    if DEFAULT_PAYLOAD_OFFSET < candidate <= len(image):
        return candidate
    return len(image)


def rsa_blob_to_int(blob: bytes) -> int:
    if len(blob) != 0x100:
        raise ValueError(f"expected 256-byte RSA blob, got {len(blob)} bytes")
    return int.from_bytes(swap_bytes_per_word(blob), "big")


def payload_digest(image: bytes, payload_offset: int, hash_end: int) -> bytes:
    if payload_offset >= hash_end:
        raise ValueError("payload offset must be before hash end")
    return hashlib.sha256(image[payload_offset:hash_end]).digest()


def payload_hash_word0(image: bytes, payload_offset: int, hash_end: int) -> int:
    return int.from_bytes(payload_digest(image, payload_offset, hash_end)[:4], "big")


def decrypt_signature_word0(
    image: bytes,
    sig_offset: int,
    key_offset: int,
    exponent: int,
) -> tuple[int, bytes]:
    sig = image[sig_offset : sig_offset + 0x100]
    key = image[key_offset : key_offset + 0x100]
    sig_int = rsa_blob_to_int(sig)
    key_int = rsa_blob_to_int(key)
    if not 0 < sig_int < key_int:
        raise ValueError("invalid RSA operands after T31 word-swap interpretation")
    decrypted = pow(sig_int, exponent, key_int).to_bytes(256, "big")
    return int.from_bytes(decrypted[:4], "big"), decrypted


@dataclass(frozen=True)
class VerificationResult:
    exponent: int
    hash_end: int
    target_word: int
    hash_word: int
    digest: bytes
    decrypted: bytes

    @property
    def matches(self) -> bool:
        return self.target_word == self.hash_word


def verify_image(
    image: bytes,
    *,
    sig_offset: int = DEFAULT_SIG_OFFSET,
    key_offset: int = DEFAULT_KEY_OFFSET,
    payload_offset: int = DEFAULT_PAYLOAD_OFFSET,
    hash_end: int | None = None,
    hash_end_field_offset: int = DEFAULT_HASH_END_FIELD_OFFSET,
    exponent: int = 65537,
) -> VerificationResult:
    resolved_hash_end = resolve_hash_end(image, hash_end, hash_end_field_offset)
    hash_word = payload_hash_word0(image, payload_offset, resolved_hash_end)
    digest = payload_digest(image, payload_offset, resolved_hash_end)
    target_word, decrypted = decrypt_signature_word0(image, sig_offset, key_offset, exponent)
    return VerificationResult(
        exponent=exponent,
        hash_end=resolved_hash_end,
        target_word=target_word,
        hash_word=hash_word,
        digest=digest,
        decrypted=decrypted,
    )


def select_verification_result(
    image: bytes,
    *,
    sig_offset: int = DEFAULT_SIG_OFFSET,
    key_offset: int = DEFAULT_KEY_OFFSET,
    payload_offset: int = DEFAULT_PAYLOAD_OFFSET,
    hash_end: int | None = None,
    hash_end_field_offset: int = DEFAULT_HASH_END_FIELD_OFFSET,
    exponent: int | str = "auto",
) -> VerificationResult:
    exponents = SUPPORTED_EXPONENTS if exponent == "auto" else (int(exponent),)
    results = []
    last_error = None
    for choice in exponents:
        try:
            results.append(
                verify_image(
                    image,
                    sig_offset=sig_offset,
                    key_offset=key_offset,
                    payload_offset=payload_offset,
                    hash_end=hash_end,
                    hash_end_field_offset=hash_end_field_offset,
                    exponent=choice,
                )
            )
        except ValueError as error:
            last_error = error
    if not results:
        raise ValueError(str(last_error) if last_error else "no valid exponent candidates")
    return next((result for result in results if result.matches), results[0])


def merge_reference_header(reference: bytes, candidate: bytes, payload_offset: int) -> bytearray:
    size = max(len(reference), len(candidate))
    merged = bytearray(reference.ljust(size, b"\x00"))
    merged[payload_offset : payload_offset + len(candidate[payload_offset:])] = candidate[payload_offset:]
    return merged


def patch_nonce(buffer: bytearray, absolute_offset: int, nonce: int, byteorder: str = "little") -> None:
    buffer[absolute_offset : absolute_offset + 4] = nonce.to_bytes(4, byteorder, signed=False)


def compute_crc7(data: bytes, skip: int = SKIP_SIZE, end: int | None = None) -> int:
    if end is None:
        end = len(data)
    crc = 0
    for byte in data[skip:end]:
        crc = CRC7_SYNDROME_TABLE[((crc << 1) ^ byte) & 0xFF]
    return crc & 0xFF


def patch_crc7(buffer: bytearray, skip: int = SKIP_SIZE, end: int | None = None) -> None:
    buffer[CRC_POSITION] = compute_crc7(bytes(buffer), skip, end)