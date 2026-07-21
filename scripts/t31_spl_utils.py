#!/usr/bin/env python3

from __future__ import annotations

import hashlib
from dataclasses import dataclass

DEFAULT_SIG_OFFSET = 0x200
DEFAULT_KEY_OFFSET = 0x300
DEFAULT_PAYLOAD_OFFSET = 0x800
DEFAULT_HASH_END_FIELD_OFFSET = 0x0C
SUPPORTED_EXPONENTS = (65537, 3)


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