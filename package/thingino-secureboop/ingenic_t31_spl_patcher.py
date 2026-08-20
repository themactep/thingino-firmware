#!/usr/bin/env python3
"""Patch a T31 SPL image to pass the bootrom's partial secure-boot verification.

The T31 flash-boot verifier compares only a single 32-bit word of the RSA-2048
signature output against the SHA-256 payload digest.  A meet-in-the-middle
collision on the 32-bit value finds a valid (signature, nonce) pair in seconds
(~2^17-2^18 ops) without the OEM signing key.

Usage::

    ingenic_t31_spl_patcher.py extract stock.bin
    ingenic_t31_spl_patcher.py patch --modulus <hex> --in-place u-boot-*.bin
    ingenic_t31_spl_patcher.py patch device.t31key firmware.bin -o out/ --nor

Authorized interoperability / recovery on hardware you own.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import struct
import subprocess
import sys
import time

try:
    from gmpy2 import mpz, powmod as _gmpy_powmod
    _HAVE_GMPY2 = True
except ImportError:                              # pragma: no cover
    _HAVE_GMPY2 = False

# Layout constants -- from HW-validated boot ROM analysis.
INGE_MAGIC = 0x45474E49
MSPL_MAGIC = 0x4D53504C
SPL_PAD_TO = 26624           # CONFIG_SPL_PAD_TO (SD SPL slot size)
SPL_BLOCK = 34               # SD block for the SPL
UBOOT_BLOCK = 86             # SD block for U-Boot (SPL_PAD_TO/512 + 34)
HEADER_SIZE = 0x800          # SPL header; the hashed payload starts here
RSA_SIG_OFF = 0x200
RSA_MOD_OFF = 0x300
RSA_SIZE = 256
SHA_BLOCK = 64
KEY_MAGIC = "t31-spl-key"
HEADER_SIGNATURE = bytes((0x55, 0xAA, 0x55, 0xAA))   # XBurst1 load-header sig @ +5
LOAD_HEADER_LEN = 0x0C   # NOR SPL bytes 0..0x0b (marker+magic+SFC cfg); size is at 0x0c


def _silent(*_args) -> None:
    """No-op default logger."""


def wordswap(data: bytes) -> bytes:
    """Reverse bytes within each 4-byte word (the T31 RSA engine's word order)."""
    out = bytearray(len(data))
    for i in range(0, len(data), 4):
        out[i:i + 4] = data[i:i + 4][::-1]
    return bytes(out)


def compute_target(sig: bytes, mod: bytes, exponent: int) -> int:
    """The word the ROM expects: first 4 bytes of (sig^e mod N), as a LE u32."""
    sig_int = int.from_bytes(wordswap(sig), "big")
    mod_int = int.from_bytes(wordswap(mod), "big")
    result_be = pow(sig_int, exponent, mod_int).to_bytes(RSA_SIZE, "big")
    return struct.unpack_from("<I", result_be, 0)[0]


def build_inge_block(total_size: int) -> bytes:
    inge = bytearray(512)
    struct.pack_into("<I", inge, 0, INGE_MAGIC)
    struct.pack_into("<I", inge, 4, total_size)
    struct.pack_into("<I", inge, 32, 0xFFFFFFFF)   # descriptor terminator
    return bytes(inge)


def build_sd_image(inge_block: bytes, patched_spl: bytes, uboot_img: bytes) -> bytes:
    """SD layout the T31 ROM boots: INGE @block 0, SPL @block 34, U-Boot @block 86."""
    sd = bytearray(inge_block)
    sd += b"\x00" * (SPL_BLOCK * 512 - len(inge_block))            # blocks 1..33
    sd += patched_spl + b"\x00" * (SPL_PAD_TO - len(patched_spl))    # blocks 34..85
    sd += uboot_img                                                # blocks 86+
    return bytes(sd)


def write_sd_device(sd_path: str, dev: str) -> None:
    """dd the SD image to a device, then add a FAT32 data partition after it."""
    subprocess.run(["sudo", "dd", f"if={sd_path}", f"of={dev}", "bs=512", "conv=fsync"], check=True)
    subprocess.run(["sudo", "parted", dev, "--script", "mklabel", "msdos",
                    "mkpart", "primary", "fat32", "1MiB", "100%"], check=True)
    # parted rewrites the MBR; restore the 36-byte INGE header the ROM reads.
    subprocess.run(["sudo", "dd", f"if={sd_path}", f"of={dev}", "bs=1", "count=36",
                    "conv=notrunc,fsync"], check=True)
    subprocess.run(["sudo", "partprobe", dev], check=True)
    subprocess.run(["sudo", "mkfs.vfat", "-F", "32", f"{dev}1"], check=True)
    subprocess.run(["sync"], check=True)


def has_load_header(data: bytes) -> bool:
    """True if the binary starts with the XBurst1 load-header (55 AA 55 AA at +5)."""
    return len(data) > 9 and data[5:9] == HEADER_SIGNATURE


def build_spl_image(
    uboot: bytes, mod: bytes, *, tpl_mode: bool = False,
) -> tuple[bytearray, int, int]:
    """Assemble the SPL image with a placeholder signature and a trailing nonce
    block. Returns (image, total, nonce_off).

    The signature at 0x200 is filled in after collision; the modulus at 0x300 is
    the pinned vendor key. The payload (0x800..total) is padded to a multiple of
    64, and a final zeroed 64-byte block is guaranteed so the nonce never lands
    on SPL code.

    tpl_mode: the input is a u-boot-with-tpl-lzma.bin (load-header format).
    The ROM's verifier requires the payload length (size - 0x800) to be
    64-byte aligned: ``(length & 0x3F) == 0``.  Read the size from +0x0C
    and round up to the next 64-byte boundary so the check passes.  The
    ROM hashes exactly size_field bytes, so write the aligned value back.
    """
    if tpl_mode:
        existing = struct.unpack_from("<I", uboot, 0x0C)[0]
        payload_len = existing - HEADER_SIZE
        payload_len = (payload_len + SHA_BLOCK - 1) & ~(SHA_BLOCK - 1)
        total = HEADER_SIZE + payload_len
        if total < HEADER_SIZE + SHA_BLOCK or total > SPL_PAD_TO:
            raise ValueError(
                f"TPL aligned size 0x{total:x} out of range "
                f"(min 0x{HEADER_SIZE + SHA_BLOCK:x}, max SPL_PAD_TO 0x{SPL_PAD_TO:x})")
        spl_data = uboot[:total]
    else:
        spl_data = uboot[:SPL_PAD_TO]
        if struct.unpack_from("<I", spl_data, 0)[0] != MSPL_MAGIC:
            raise ValueError("U-Boot binary does not start with MSPL magic")
        total = (len(spl_data) + 511) & ~511
        while (total - HEADER_SIZE) % SHA_BLOCK != 0:
            total += SHA_BLOCK
        if total > SPL_PAD_TO:
            raise ValueError(f"SPL too large: 0x{total:x} > SPL_PAD_TO 0x{SPL_PAD_TO:x}")

    img = bytearray(total)
    img[:len(spl_data)] = spl_data
    img[total - SHA_BLOCK:total] = bytes(SHA_BLOCK)   # clear the nonce block
    img[RSA_MOD_OFF:RSA_MOD_OFF + RSA_SIZE] = mod
    struct.pack_into("<I", img, 0x0C, total)          # hashed-extent field
    return img, total, total - 4                      # nonce in the final block


def mitm_collide(
    image: bytearray, total: int, mod_int: int, exponent: int,
    nonce_off: int, table_bits: int, log=_silent,
) -> tuple[int, int, int, int]:
    """Find (sig_int, nonce) whose 32-bit words collide. Returns also (|A|, |B|)."""
    payload = bytes(image[HEADER_SIZE:total])
    nonce_rel = nonce_off - HEADER_SIZE
    block_start = (nonce_rel // SHA_BLOCK) * SHA_BLOCK
    nonce_in_tail = nonce_rel - block_start

    # Precompute the SHA-256 state up to the nonce's block once (midstate); each
    # trial then only re-hashes the short tail.
    base = hashlib.sha256(payload[:block_start])
    tail = bytearray(payload[block_start:])

    # --- Set A: |A| = 2^table_bits payload-hash words (cheap) ---
    na = 1 << table_bits
    table: dict[bytes, int] = {}
    t0 = time.monotonic()
    for nonce in range(na):
        struct.pack_into("<I", tail, nonce_in_tail, nonce)
        h = base.copy()
        h.update(tail)
        table[h.digest()[:4]] = nonce
    log(f"  set A: {len(table)} distinct words from 2^{table_bits} nonces "
        f"({time.monotonic() - t0:.1f}s)")

    # --- Set B: draw signatures until one's word hits the table (costly) ---
    # Start from a large, fixed sig_int so the modexp is non-trivial; RSA is a
    # permutation, so successive sig_int give ~uniform result words. gmpy2's
    # powmod is ~10x Python's pow when available.
    expected = max(1, (1 << 32) // max(1, len(table)))
    cap = expected * 64                          # ~e^-64 chance of missing
    t1 = time.monotonic()
    engine = "gmpy2" if _HAVE_GMPY2 else "python pow"
    if _HAVE_GMPY2:
        s, m = mpz(mod_int // 3), mpz(mod_int)
    else:
        s, m = mod_int // 3, mod_int
    for nb in range(1, cap + 1):
        if _HAVE_GMPY2:
            word = int(_gmpy_powmod(s, exponent, m)).to_bytes(RSA_SIZE, "big")[:4]
        else:
            word = pow(s, exponent, m).to_bytes(RSA_SIZE, "big")[:4]
        nonce = table.get(word)
        if nonce is not None:
            log(f"  set B: hit after {nb} modexps (expected ~{expected}, "
                f"{time.monotonic() - t1:.1f}s, {engine})")
            return int(s), nonce, na, nb
        s += 1
    raise RuntimeError(
        f"no collision in {cap} modexps; raise --table-bits (currently {table_bits})"
    )


def splice_uboot_offset(firmware: bytes) -> int:
    """Where the MSPL SPL lives inside a full firmware image. Checks offset 0
    (bare SFC), block 34 (SD/MMC with or without INGE header at block 0)."""
    for off in [0, SPL_BLOCK * 512]:
        if off + 4 <= len(firmware) and struct.unpack_from("<I", firmware, off)[0] == MSPL_MAGIC:
            return off
    raise ValueError("no MSPL magic at offset 0x0 or block 34")


def locate_modulus(stock: bytes) -> tuple[bytes, int]:
    """Find the SPL header in a stock flash dump and return (modulus_bytes,
    header_offset).

    The SPL sits at flash offset 0 (NOR) or block 34 (SD) and begins with the
    XBurst1 bootrom load-header (55 aa 55 aa at +5) -- the T31 vendor SPL does
    NOT carry an MSPL magic -- or, for a thingino/SD image, the MSPL magic. The
    RSA modulus is 0x300 into the header; it is validated as a plausible RSA-2048
    key (2048-bit, odd) so a stray header match can't yield garbage.
    """
    def header_at(off: int) -> bool:
        if off + max(9, RSA_MOD_OFF + RSA_SIZE) > len(stock):
            return False
        if stock[off + 5:off + 9] == HEADER_SIGNATURE:
            return True
        return struct.unpack_from("<I", stock, off)[0] == MSPL_MAGIC

    def modulus_ok(off: int) -> bool:
        n = int.from_bytes(wordswap(stock[off + RSA_MOD_OFF:off + RSA_MOD_OFF + RSA_SIZE]), "big")
        return n.bit_length() >= 2040 and n % 2 == 1

    tried = [0, SPL_BLOCK * 512]
    scan = [o for o in range(0, min(len(stock), 1 << 20), 512) if o not in tried]
    for off in tried + scan:
        if header_at(off) and modulus_ok(off):
            return stock[off + RSA_MOD_OFF:off + RSA_MOD_OFF + RSA_SIZE], off
    raise ValueError("no SPL header with a valid RSA modulus (checked offset 0, "
                     "block 34, and a 1 MiB scan)")


def read_key_file(data: bytes) -> dict | None:
    """Parse a key file, or return None if `data` is not one (e.g. a flash dump)."""
    try:
        obj = json.loads(data)
    except (ValueError, UnicodeDecodeError):
        return None
    return obj if isinstance(obj, dict) and obj.get("magic") == KEY_MAGIC else None


def write_key_file(path: str, mod: bytes, exponent: int, load_header: bytes) -> None:
    obj = {"magic": KEY_MAGIC, "version": 1, "exponent": exponent,
           "modulus": mod.hex(), "load_header": load_header.hex()}
    with open(path, "w") as f:
        json.dump(obj, f, indent=2)
        f.write("\n")


def load_modulus(path: str, exponent_override: int | None):
    """Resolve modulus + exponent + NOR load-header from a key file *or* a stock
    dump. Returns (mod_bytes, mod_int, exponent, source_label, load_header|None).
    """
    data = open(path, "rb").read()
    key = read_key_file(data)
    if key is not None:
        mod = bytes.fromhex(key["modulus"])
        exponent = exponent_override or int(key.get("exponent", 65537))
        load_header = bytes.fromhex(key["load_header"]) if key.get("load_header") else None
        source = "key file"
    else:
        mod, off = locate_modulus(data)
        exponent = exponent_override or 65537
        load_header = data[off:off + LOAD_HEADER_LEN]
        source = f"stock dump (SPL @0x{off:x})"
    if not any(mod):
        raise ValueError("modulus is all zeros")
    mod_int = int.from_bytes(wordswap(mod), "big")
    if mod_int % 2 == 0:
        print("warning: modulus is even -- not a valid RSA key?", file=sys.stderr)
    return mod, mod_int, exponent, source, load_header


def resolve_key(args):
    """Key material from an explicit --modulus (hex string) if given, else from the
    key file / stock dump. Returns (mod, mod_int, exponent, source, load_header)."""
    if not args.modulus:
        if not args.key:
            raise ValueError("give a key file / stock dump, or --modulus <hex>")
        return load_modulus(args.key, args.exponent)

    mod = bytes.fromhex(args.modulus.strip())
    if len(mod) != RSA_SIZE:
        raise ValueError(f"--modulus must be {RSA_SIZE} bytes "
                         f"({RSA_SIZE * 2} hex chars), got {len(mod)}")
    if not any(mod):
        raise ValueError("modulus is all zeros")
    load_header = bytes.fromhex(args.load_header.strip()) if args.load_header else None
    mod_int = int.from_bytes(wordswap(mod), "big")
    if mod_int % 2 == 0:
        print("warning: modulus is even -- not a valid RSA key?", file=sys.stderr)
    return mod, mod_int, args.exponent or 65537, "--modulus", load_header


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        description=__doc__.splitlines()[0],
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="Authorized interoperability / recovery use on hardware you own.",
    )
    sub = p.add_subparsers(dest="cmd", required=True)

    pe = sub.add_parser("extract", help="pull the RSA modulus from a stock dump "
                        "into a small reusable key file")
    pe.add_argument("stock", help="stock flash dump (NOR at 0, or SD with SPL at block 34)")
    pe.add_argument("-o", "--output", help="key file to write (default: <stock>.t31key)")
    pe.add_argument("-e", "--exponent", type=int, default=65537,
                    help="RSA exponent to record (target's eFuse choice; default 65537)")

    pf = sub.add_parser("patch", help="patch an SPL to pass verification, using a "
                        "key file / stock dump or an explicit --modulus")
    pf.add_argument("key", nargs="?",
                    help="key file from 'extract', or a stock dump (omit if --modulus)")
    pf.add_argument("firmware", help="u-boot-*-with-spl.bin (MSPL) or full firmware image")
    pf.add_argument("--modulus", metavar="HEX",
                    help="RSA modulus as hex (256 bytes / 512 chars), instead of a key "
                         "file -- it is the public key, fine to keep in a defconfig")
    pf.add_argument("--load-header", metavar="HEX",
                    help="NOR load-header as hex (12 bytes); with --modulus, for --nor")
    pf.add_argument("-o", "--output", default=".", help="output directory")
    pf.add_argument("-e", "--exponent", type=int, default=None,
                    help="override the RSA exponent (default: from key file, else 65537)")
    pf.add_argument("--table-bits", type=int, default=None,
                    help="log2 of the payload-side table size (default: 18 with "
                         "gmpy2, else 20); higher = more RAM/SHAs but fewer modexps")
    pf.add_argument("--in-place", action="store_true",
                    help="patch the firmware file in-place: patch the signature "
                         "and nonce, write back to the same path, do not change "
                         "the header format or assemble an image")
    pf.add_argument("--nor", action="store_true",
                    help="emit a NOR-flashable SPL (load-header at offset 0, for "
                         "flash offset 0) instead of an SD image; needs the "
                         "load-header, which extract records from the stock dump")
    pf.add_argument("-d", "--device",
                    help="SD device to write the image to (e.g. /dev/sdf); adds a "
                         "FAT32 data partition after the boot area")
    return p


def cmd_extract(args) -> int:
    stock = open(args.stock, "rb").read()
    mod, off = locate_modulus(stock)
    load_header = stock[off:off + LOAD_HEADER_LEN]
    out = args.output or (args.stock + ".t31key")
    write_key_file(out, mod, args.exponent, load_header)
    tool = os.path.basename(sys.argv[0])
    print(f"stock:       {args.stock}  (SPL header at 0x{off:x})")
    print(f"exponent:    {args.exponent}")
    print(f"load-header: {load_header.hex()}   (NOR only)")
    print(f"modulus:     (256 bytes, sha256 {hashlib.sha256(mod).hexdigest()[:16]}...)")
    print(f"  {mod.hex()}")
    print(f"key file:    {out}  ({os.path.getsize(out)} bytes)")
    print(f"use a file:  {tool} patch {out} <firmware> [--nor]")
    print(f"or a string: {tool} patch --modulus <above> "
          f"[--load-header {load_header.hex()}] <firmware> [--nor]")
    return 0


def cmd_patch(args) -> int:
    mod, mod_int, exponent, source, load_header = resolve_key(args)
    firmware = open(args.firmware, "rb").read()
    in_place = getattr(args, "in_place", False)

    print("=== T31 secure-boot patch (meet-in-the-middle) ===")
    print(f"modulus:     from {source}; exponent {exponent}")

    # Detect input format: bare MSPL, TPL (load-header), or full firmware.
    tpl_mode = False
    if struct.unpack_from("<I", firmware, 0)[0] == MSPL_MAGIC:
        uboot, splice_off = firmware, None
        print("mode:        u-boot-with-spl (MSPL)")
    elif has_load_header(firmware):
        uboot, splice_off = firmware, None
        tpl_mode = True
        print("mode:        u-boot-with-tpl (load-header)")
    else:
        splice_off = splice_uboot_offset(firmware)
        uboot = firmware[splice_off:splice_off + SPL_PAD_TO]
        print(f"mode:        full firmware; SPL at 0x{splice_off:x}")

    image, total, nonce_off = build_spl_image(uboot, mod, tpl_mode=tpl_mode)
    print(f"SPL image:   {total} bytes (0x{total:x}), nonce at 0x{nonce_off:x}")

    table_bits = args.table_bits if args.table_bits is not None else (18 if _HAVE_GMPY2 else 20)
    print(f"searching (MITM, table 2^{table_bits}, {'gmpy2' if _HAVE_GMPY2 else 'python pow'})...")
    t0 = time.monotonic()
    sig_int, nonce, na, nb = mitm_collide(
        image, total, mod_int, exponent, nonce_off, table_bits, print)
    elapsed = time.monotonic() - t0

    struct.pack_into("<I", image, nonce_off, nonce)
    sig = wordswap(sig_int.to_bytes(RSA_SIZE, "big"))
    image[RSA_SIG_OFF:RSA_SIG_OFF + RSA_SIZE] = sig

    target = compute_target(sig, mod, exponent)
    hw = struct.unpack_from("<I", hashlib.sha256(bytes(image[HEADER_SIZE:total])).digest(), 0)[0]
    if hw != target:
        print(f"error: verify failed (hash 0x{hw:08x} != target 0x{target:08x})",
              file=sys.stderr)
        return 2

    total_ops = na + nb
    print(f"matched:     word 0x{target:08x}  in {elapsed:.1f}s")
    print(f"work:        2^{table_bits} SHA + {nb} modexp = ~2^{total_ops.bit_length()-1} ops "
          f"(vs 2^32 brute-force)")
    print(f"verified:    SHA256(payload)[:4] == (sig^e mod N)[:4] = 0x{target:08x}")

    # --in-place: write the patched SPL region back into the original file,
    # preserving the header format (MSPL or load-header) and any data past
    # the SPL.  The build system handles image layout.
    if in_place:
        patched = bytearray(firmware)
        off = splice_off or 0
        patched[off:off + len(image)] = image
        open(args.firmware, "wb").write(patched)
        print(f"patched:     {args.firmware}  (in-place, {len(patched)} bytes)")
        return 0

    os.makedirs(args.output, exist_ok=True)
    print("\n=== output ===")

    if args.nor:
        if not load_header:
            raise ValueError("--nor needs the load-header; extract the key from a "
                             "stock dump (a key made before --nor support lacks it)")
        image[0:LOAD_HEADER_LEN] = load_header
        nor_path = os.path.join(args.output, "patched_nor_spl.bin")
        open(nor_path, "wb").write(image)
        print(f"  {nor_path}  ({len(image)} bytes, NOR SPL -> flash at offset 0)")
        print(f"    header {load_header.hex()}  size@0x0c=0x{total:x}")
        print(f"    flash: sf write <addr> 0 0x{len(image):x}  (or flashrom a full "
              "image with this at offset 0)")
        return 0

    patched_spl = bytes(image)
    spl_path = os.path.join(args.output, "patched_spl.bin")
    open(spl_path, "wb").write(patched_spl)
    print(f"  {spl_path}  ({len(patched_spl)} bytes)")
    if splice_off is not None:
        patched = bytearray(firmware)
        patched[splice_off:splice_off + len(patched_spl)] = patched_spl
        if struct.unpack_from("<I", firmware, 0)[0] == INGE_MAGIC:
            patched[0:36] = build_inge_block(total)[:36]
        out_path = os.path.join(args.output, os.path.basename(args.firmware))
        open(out_path, "wb").write(patched)
        print(f"  {out_path}  ({len(patched)} bytes, patched SPL spliced at 0x{splice_off:x})")
        if args.device:
            subprocess.run(["sudo", "dd", f"if={out_path}", f"of={args.device}",
                            "bs=1M", "conv=fsync"], check=True)
            subprocess.run(["sync"], check=True)
            print(f"  wrote {args.device}")
    else:
        uboot_img = firmware[SPL_PAD_TO:]
        sd = build_sd_image(build_inge_block(total), patched_spl, uboot_img)
        sd_path = os.path.join(args.output, "sd_image.bin")
        open(sd_path, "wb").write(sd)
        print(f"  {sd_path}  ({len(sd)} bytes, complete SD image)")
        print(f"    block 0:   INGE (total 0x{total:x})")
        print(f"    block {SPL_BLOCK}:  patched SPL ({len(patched_spl)} B, padded to 0x{SPL_PAD_TO:x})")
        print(f"    block {UBOOT_BLOCK}:  U-Boot ({len(uboot_img)} bytes)")
        if not uboot_img:
            print("  warning: nothing after the SPL region -- expected "
                  "u-boot-*-with-spl.bin (SPL + U-Boot)", file=sys.stderr)
        if args.device:
            write_sd_device(sd_path, args.device)
            print(f"  wrote {args.device} (+ FAT32 data partition)")
        else:
            print(f"  flash: sudo dd if={sd_path} of=/dev/sdX bs=1M conv=fsync")
    return 0


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        return cmd_extract(args) if args.cmd == "extract" else cmd_patch(args)
    except (ValueError, OSError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
