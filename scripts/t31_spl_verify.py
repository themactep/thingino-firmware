#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
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
    parser = argparse.ArgumentParser(description="Verify T31 SPL single-word secure-boot state")
    parser.add_argument("image", type=Path)
    parser.add_argument("--sig-offset", type=parse_int, default=DEFAULT_SIG_OFFSET)
    parser.add_argument("--key-offset", type=parse_int, default=DEFAULT_KEY_OFFSET)
    parser.add_argument("--payload-offset", type=parse_int, default=DEFAULT_PAYLOAD_OFFSET)
    parser.add_argument("--hash-end", type=parse_int)
    parser.add_argument("--hash-end-field-offset", type=parse_int, default=DEFAULT_HASH_END_FIELD_OFFSET)
    parser.add_argument("--exponent", default="auto", choices=("auto", "3", "65537"))
    parser.add_argument("--json", action="store_true")
    return parser


def main() -> int:
    args = build_parser().parse_args()
    image = args.image.read_bytes()
    result = select_verification_result(
        image,
        sig_offset=args.sig_offset,
        key_offset=args.key_offset,
        payload_offset=args.payload_offset,
        hash_end=args.hash_end,
        hash_end_field_offset=args.hash_end_field_offset,
        exponent=args.exponent,
    )

    payload = {
        "image": str(args.image),
        "image_size": len(image),
        "hash_end": result.hash_end,
        "payload_offset": args.payload_offset,
        "sig_offset": args.sig_offset,
        "key_offset": args.key_offset,
        "exponent": result.exponent,
        "target_word": f"0x{result.target_word:08x}",
        "hash_word": f"0x{result.hash_word:08x}",
        "sha256": result.digest.hex(),
        "match": result.matches,
    }

    if args.json:
        print(json.dumps(payload, indent=2, sort_keys=True))
    else:
        print(f"image        : {payload['image']}")
        print(f"image size   : 0x{len(image):x}")
        print(f"payload range: 0x{args.payload_offset:x}:0x{result.hash_end:x}")
        print(f"layout       : sig@0x{args.sig_offset:x}, key@0x{args.key_offset:x}")
        print(f"exponent     : {result.exponent}")
        print(f"target word  : {payload['target_word']}")
        print(f"hash word 0  : {payload['hash_word']}")
        print(f"sha256       : {payload['sha256']}")
        print(f"match        : {payload['match']}")

    return 0 if result.matches else 1


if __name__ == "__main__":
    raise SystemExit(main())