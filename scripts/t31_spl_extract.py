#!/usr/bin/env python3

from __future__ import annotations

import argparse
from pathlib import Path

from t31_spl_utils import (
    DEFAULT_HASH_END_FIELD_OFFSET,
    DEFAULT_KEY_OFFSET,
    DEFAULT_PAYLOAD_OFFSET,
    DEFAULT_SIG_OFFSET,
    parse_int,
    select_verification_result,
)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Extract a signed T31 SPL reference from a full firmware dump",
        epilog="Only the first 0x800 bytes (header with signature and key) are written to the output file.",
    )
    parser.add_argument("firmware", type=Path)
    parser.add_argument("--output", "-o", type=Path, required=True)
    parser.add_argument("--spl-offset", type=parse_int, default=0, help="Absolute SPL offset in the firmware dump")
    parser.add_argument("--size", type=parse_int, help="Number of bytes to extract; defaults to --hash-end")
    parser.add_argument("--hash-end", type=parse_int, help="SPL-relative secure hash end, commonly 0x4b80")
    parser.add_argument("--sig-offset", type=parse_int, default=DEFAULT_SIG_OFFSET)
    parser.add_argument("--key-offset", type=parse_int, default=DEFAULT_KEY_OFFSET)
    parser.add_argument("--payload-offset", type=parse_int, default=DEFAULT_PAYLOAD_OFFSET)
    parser.add_argument("--hash-end-field-offset", type=parse_int, default=DEFAULT_HASH_END_FIELD_OFFSET)
    parser.add_argument("--exponent", default="auto", choices=("auto", "3", "65537"))
    parser.add_argument("--no-verify", action="store_true", help="Write the slice without checking the SPL signature")
    return parser


def slice_spl(firmware: bytes, spl_offset: int, size: int) -> bytes:
    if spl_offset < 0:
        raise ValueError("SPL offset must be non-negative")
    if size <= 0:
        raise ValueError("SPL extract size must be positive")

    end = spl_offset + size
    if end > len(firmware):
        raise ValueError(
            f"requested slice 0x{spl_offset:x}:0x{end:x} exceeds firmware size 0x{len(firmware):x}"
        )
    return firmware[spl_offset:end]


def main() -> int:
    args = build_parser().parse_args()
    size = args.size or args.hash_end
    if size is None:
        raise SystemExit("ERROR: set --hash-end or --size so the extractor does not write the full firmware dump")
    if args.hash_end is not None and size < args.hash_end:
        raise SystemExit("ERROR: --size must be greater than or equal to --hash-end")

    firmware = args.firmware.read_bytes()
    try:
        spl = slice_spl(firmware, args.spl_offset, size)
    except ValueError as error:
        raise SystemExit(f"ERROR: {error}") from error

    result = None
    if not args.no_verify:
        try:
            result = select_verification_result(
                spl,
                sig_offset=args.sig_offset,
                key_offset=args.key_offset,
                payload_offset=args.payload_offset,
                hash_end=args.hash_end,
                hash_end_field_offset=args.hash_end_field_offset,
                exponent=args.exponent,
            )
        except ValueError as error:
            raise SystemExit(f"ERROR: extracted SPL could not be verified: {error}") from error
        if not result.matches:
            raise SystemExit(
                "ERROR: extracted SPL verification failed "
                f"(target=0x{result.target_word:08x}, hash=0x{result.hash_word:08x})"
            )

    args.output.parent.mkdir(parents=True, exist_ok=True)
    # Only the header (hash-end field, signature, key) is needed for forging.
    # Truncate the written reference to DEFAULT_PAYLOAD_OFFSET bytes.
    header_only = spl[:DEFAULT_PAYLOAD_OFFSET]
    args.output.write_bytes(header_only)

    print(f"firmware    : {args.firmware}")
    print(f"output      : {args.output}")
    print(f"spl offset  : 0x{args.spl_offset:x}")
    print(f"spl size    : 0x{len(spl):x}")
    if result is not None:
        print(f"payload range: 0x{args.payload_offset:x}:0x{result.hash_end:x}")
        print(f"exponent    : {result.exponent}")
        print(f"target word : 0x{result.target_word:08x}")
        print(f"hash word 0 : 0x{result.hash_word:08x}")
        print("match       : True")
    else:
        print("match       : skipped")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
