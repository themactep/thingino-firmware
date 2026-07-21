#!/usr/bin/env python3
"""Inject a T32 pre-verification init-table patch into a full firmware image.

Confirmed working against the Ingenic T32 bootrom (Wyze Pan v4, 2025-03-26).

T32 Bootrom Secure Boot Flow (SFC path — sub_bfc02410)
=======================================================

  1. sub_bfc00140 reads eFuse registers on every boot:
       *0x80000024 = eFuse 0xB3540210   (secureboot / RSA config)
       *0x80000020 = eFuse 0xB3540214   (AES / halt-on-failure config)
       *0x8000002c = 0x800              (SPL entry-point offset, hardcoded)
       *0x80000014 = 0x80001000         (SPL load base address, hardcoded)

  2. SFC handler reads 0x200-byte SPL header from flash offset 0 → 0x80001000.

  3. Init-table parser (sub_bfc03d3c) runs on header+0x100 = 0x80001100
     **BEFORE** any signature verification:
       - Checks for "INGE" magic (0x45474E49) at +0x00
       - Optional payload-size override at +0x04
       - Optional timing/delay value at +0x08
       - SFC clock config data copied from +0x10..+0x1F
       - Init entries start at +0x20, each 0x14 (20) bytes:
           [+0x00] addr       — target SRAM/register address (0xFFFFFFFF = skip)
           [+0x04] mask_addr  — poll address (0xFFFFFFFF / ~0 = no poll)
           [+0x08] value      — 32-bit value written to *addr
           [+0x0C] poll_val   — wait-for-set mask on *mask_addr (0 = skip)
           [+0x10] poll_clr   — wait-for-clear mask on *mask_addr (0 = skip)
       - Terminator: addr=0xFFFFFFFF AND mask_addr=0xFFFFFFFF
       - Max 11 entries before the parser stops.

  4. Full SPL payload is read from flash (size from header bytes 12..15).

  5. Secureboot check: if (*0x80000024 & 0x10000) != 0
       → RSA-PSS verification via sub_bfc048d0
       → Key at SPL+0x200, signature at SPL+0x300
       → Failure returns -1 (boot rejected)

  6. AES decryption check: if (*0x80000020 & 0x100000) != 0
       → sub_bfc045e8 decrypts payload using params from SPL header
       → AES flag is at 0x80000020 (eFuse 0xB3540214), NOT 0x80000024
       → Zeroing 0x80000024 does NOT affect AES operation

  7. Jump to entry point: sub_bfc00604(*0x80000014 + *0x8000002c)
       = 0x80001000 + 0x800 = 0x80001800

Bypass mechanism
================
Writing 0x00000000 to *0x80000024 via init-table clears bit 16 (secureboot
enable).  The bootrom processes init-table entries before checking the
secureboot flag, so the write takes effect before verification runs.

Other bits in *0x80000024 (confirmed from bootrom disassembly):
  - Bit 16 (0x10000):  Secure boot enable
  - Bit 18 (0x40000):  RSA exponent select (e=3 vs e=65537)
  - Bit 19 (0x80000):  NAND secure boot lockout (with bit 16)
  - Bit 20 (0x100000): USB boot disable (with bit 16 → blocks USB recovery)

Zeroing the full word is safe: all non-secureboot bits are either unused or
only restrict boot options (USB disable, NAND lockout).

Important notes
===============
- The SPL payload must NOT be corrupted.  The init-table only disables the
  bootrom's RSA-PSS check; the SPL code itself must be valid MIPS to execute.
  A previous test failure was caused by applying this patch to an image that
  already had a corrupted byte at 0x800 — always patch from a clean base.

- The SPL's own U-Boot code may have a downstream signature check
  ("verify signature uboot error" string at ~0x4D04).  This patch only
  bypasses the bootrom-level check.

- Verified on Wyze Pan v4 (T32 SoC, SPI NOR boot, 16 MB flash):
  Modified SPL build string (2025→2026) + init-table bypass → boots
  successfully, confirming secureboot was active and the bypass works.
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
ENTRY_SIZE = 0x14  # 20 bytes per entry (addr, mask_addr, value, poll_val, poll_clr)
TERM_OFFSET = ENTRY0_OFFSET + ENTRY_SIZE  # terminator follows first entry
PATCH_LEN = 0x48  # total bytes touched: 0x100..0x147

# T32 SRAM addresses (populated by bootrom from eFuse on every boot)
SECUREBOOT_ADDR = 0x80000024  # eFuse 0xB3540210 — bit 16 = secureboot enable
AES_CONFIG_ADDR = 0x80000020  # eFuse 0xB3540214 — bit 20 = AES decrypt enable
SPL_LOAD_BASE = 0x80001000  # hardcoded in bootrom
SPL_ENTRY_OFF = 0x800  # hardcoded in bootrom (*0x8000002c)

MAX_INIT_ENTRIES = 11  # bootrom stops after 11 entries


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
    """Inject an INGE init-table into the SPL header's blank region.

    Writes a single init-table entry that stores ``write_value`` at
    ``target_addr`` in SRAM, followed by a terminator entry.  The
    bootrom (sub_bfc03d3c) processes this before signature verification.
    """
    start = boot_offset + INIT_OFFSET
    end = start + PATCH_LEN
    if end > len(data):
        raise ValueError("image too small for init-table injection at requested boot offset")

    region = data[start:end]
    if not force and any(region):
        raise ValueError(
            f"init-table region {start:#x}..{end - 1:#x} is not blank; rerun with --force to overwrite"
        )

    # --- init-table header (12 bytes at +0x100) ---
    # +0x00: INGE magic
    # +0x04: payload-size override (0 = keep default from header bytes 12..15)
    # +0x08: timing/delay value (0 = skip)
    struct.pack_into("<III", data, boot_offset + INIT_OFFSET, MAGIC, 0, 0)

    # --- entry 0 (20 bytes at +0x120) ---
    # addr=target, mask_addr=0xFFFFFFFF (→ NULL after not.d, no poll),
    # value=write_value, poll_val=0, poll_clr=0
    struct.pack_into(
        "<IIIII",
        data,
        boot_offset + ENTRY0_OFFSET,
        target_addr,
        0xFFFFFFFF,  # mask_addr: not.d(0xFFFFFFFF)==0 → treated as NULL (no poll)
        write_value,
        0,  # poll_val (unused when mask_addr is NULL)
        0,  # poll_clr (unused when mask_addr is NULL)
    )

    # --- terminator (20 bytes at +0x134) ---
    # addr=0xFFFFFFFF AND mask_addr=0xFFFFFFFF → parser breaks out of loop
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
            "The init-table is processed by the bootrom (sub_bfc03d3c) BEFORE RSA-PSS "
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
        help=f"32-bit SRAM address to write (default: {SECUREBOOT_ADDR:#x} — secureboot config)",
    )
    parser.add_argument(
        "--write-value",
        type=parse_int,
        default=0,
        help="32-bit value to write to --target-addr (default: 0x0 — clears all security bits)",
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
        # Common MIPS opcodes: R-type(0), j/jal(2-3), branches(4-7),
        # addiu(9), andi/ori/xori/lui(0xC-0xF), loads(0x20-0x25),
        # stores(0x28-0x2B), coprocessor(0x10-0x13), cache(0x2F)
        if opcode not in (
            0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 0xA, 0xB,
            0xC, 0xD, 0xE, 0xF, 0x10, 0x11, 0x12, 0x13,
            0x20, 0x21, 0x23, 0x24, 0x25, 0x28, 0x29, 0x2B, 0x2F,
        ):
            print(
                f"WARNING: first instruction at SPL entry ({spl_code_off:#x}) = {first_word:#010x} "
                f"does not look like standard MIPS.  Make sure the input image has a clean "
                f"(uncorrupted) SPL payload — patching a previously corrupted image will "
                f"produce a silent boot failure."
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