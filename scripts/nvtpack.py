#!/usr/bin/env python3
"""Unpack, pack and verify Novatek NVTPACK (FW_HDR2) all-in-one images.

Format, as U-Boot's board/novatek/common/nvt_ivot_pack.c builds and checks it:
a 128-byte NVTPACK_FW_HDR2, TotalRes 12-byte (offset, size, id) entries, then
the partitions back to back from the end of that table, each zero padded to a
multiple of 64 bytes (the vendor's PC packer; U-Boot's in-tree one pads to 4,
and readers accept either). The whole image sums
to zero under nvt_sum (16-bit words plus their index, mod 0x10000); the
header's uiChkValue is the term that makes it so. Partitions wrapped in a
64-byte CKSM header (rootfs, app) sum to zero the same way over header, data
and padding.

    nvtpack.py unpack FW98529A.bin DIR    # DIR/pNN.bin + DIR/manifest.json
    nvtpack.py pack DIR OUT.bin           # rebuild from the manifest
    nvtpack.py make OUT.bin ID:FILE...    # a new pack from partition files
    nvtpack.py verify FW98529A.bin
    nvtpack.py cksm IN OUT [--emb-type N] # wrap a partition image in CKSM
    nvtpack.py binsum u-boot.bin [--offset 0x350]  # the SDK's `encrypt_bin SUM`
"""
import argparse
import json
import struct
import sys
from pathlib import Path

GUID_FW2 = bytes.fromhex('072e01d6bc10914fb28a352f82261a50')
FW_HDR2_VERSION = 0x16071515
CKSM_VERSION = 0x16040719
HDR_SIZE = 0x80
PAD = 0x40
ENTRY = struct.Struct('<III')
# guid, uiVersion, uiHdrSize, TotalRes, TotalSize, uiChkMethod, uiChkValue,
# uiUserData[4], uiReversed[18]
FW_HDR2 = struct.Struct('<16s6I4I18I')
CKSM_HDR = struct.Struct('<4s7I8I')


def nvt_sum(data):
    if len(data) % 2:
        data += b'\0'
    words = struct.unpack(f'<{len(data) // 2}H', data)
    return (sum(words) + sum(range(len(words)))) & 0xFFFF


def neg16(value):
    return (-value) & 0xFFFF


def parse(img):
    f = FW_HDR2.unpack_from(img)
    if f[0] != GUID_FW2:
        raise ValueError('not an NVTPACK FW_HDR2 image')
    hdr = {'version': f[1], 'hdr_size': f[2], 'total_res': f[3], 'total_size': f[4],
           'chk_method': f[5], 'chk_value': f[6], 'user_data': list(f[7:11]),
           'reserved': list(f[11:29])}
    entries = [ENTRY.unpack_from(img, hdr['hdr_size'] + ENTRY.size * i)
               for i in range(hdr['total_res'])]
    return hdr, entries


def cmd_verify(args):
    img = Path(args.image).read_bytes()
    hdr, entries = parse(img)
    ok = True
    print(f"FW_HDR2 version 0x{hdr['version']:08x}, {hdr['total_res']} partitions, "
          f"total 0x{hdr['total_size']:x} (file 0x{len(img):x})")
    if hdr['total_size'] != len(img):
        print('  total size does not match the file')
        ok = False
    s = nvt_sum(img[:hdr['total_size']])
    print(f"  image sum 0x{s:04x} {'ok' if s == 0 else 'BAD'}")
    ok &= s == 0
    for off, size, pid in entries:
        blob = img[off:off + size]
        line = f'  id {pid:2d} off 0x{off:08x} size 0x{size:08x} {blob[:4]!r}'
        if blob[:4] == b'CKSM':
            c = CKSM_HDR.unpack_from(blob)
            span = c[4] + c[5] + c[6]
            cs = nvt_sum(blob[:span])
            line += f' CKSM sum 0x{cs:04x} {"ok" if cs == 0 else "BAD"}'
            ok &= cs == 0
        print(line)
    print('OK' if ok else 'FAILED')
    return 0 if ok else 1


def cmd_unpack(args):
    img = Path(args.image).read_bytes()
    hdr, entries = parse(img)
    out = Path(args.dir)
    out.mkdir(parents=True, exist_ok=True)
    parts = []
    for off, size, pid in entries:
        name = f'p{pid:02d}.bin'
        (out / name).write_bytes(img[off:off + size])
        parts.append({'id': pid, 'file': name})
    manifest = {k: hdr[k] for k in ('version', 'chk_method', 'user_data', 'reserved')}
    manifest['partitions'] = parts
    (out / 'manifest.json').write_text(json.dumps(manifest, indent=1) + '\n')
    print(f"{len(parts)} partitions -> {out}")
    return 0


def cmd_make(args):
    parts = []
    for spec in args.parts:
        pid, _, file = spec.partition(':')
        parts.append({'id': int(pid, 0), 'file': str(Path(file).resolve())})
    return build_pack({'partitions': parts}, Path('/'), args.out)


def cmd_pack(args):
    src = Path(args.dir)
    return build_pack(json.loads((src / 'manifest.json').read_text()), src, args.out)


def build_pack(m, src, out):
    parts = m['partitions']
    body = bytearray()
    table = []
    off = HDR_SIZE + ENTRY.size * len(parts)
    for p in parts:
        blob = (src / p['file']).read_bytes()
        table.append((off, len(blob), p['id']))
        pad = -len(blob) % PAD
        body += blob + b'\0' * pad
        off += len(blob) + pad
    total = off

    def build(chk):
        hdr = FW_HDR2.pack(GUID_FW2, m.get('version', FW_HDR2_VERSION), HDR_SIZE,
                           len(parts), total, m.get('chk_method', 0), chk,
                           *m.get('user_data', [0] * 4), *m.get('reserved', [0] * 18))
        return hdr + b''.join(ENTRY.pack(*e) for e in table) + body

    img = build(0)
    img = build(neg16(nvt_sum(img)))
    assert nvt_sum(img) == 0 and len(img) == total
    Path(out).write_bytes(img)
    print(f'{len(parts)} partitions, 0x{total:x} bytes -> {out}')
    return 0


def cmd_cksm(args):
    data = Path(args.input).read_bytes()
    pad = -len(data) % 4
    def build(chk):
        hdr = CKSM_HDR.pack(b'CKSM', CKSM_VERSION, 0, chk, CKSM_HDR.size, len(data), pad,
                            args.emb_type, *([0] * 8))
        return hdr + data + b'\0' * pad
    blob = build(0)
    blob = build(neg16(nvt_sum(blob)))
    assert nvt_sum(blob) == 0
    Path(args.output).write_bytes(blob)
    return 0


def cmd_binsum(args):
    """Stamp a bin-info header in place: length at +0x18, then 0xAA55 and the
    halfword that brings the whole file's nvt_sum to 0 at +0x1C/+0x1E."""
    path = Path(args.file)
    b = bytearray(path.read_bytes())
    o = args.offset
    if len(b) % 2:
        sys.exit('odd-sized binary')
    struct.pack_into('<IHH', b, o + 0x18, len(b), 0xAA55, 0)
    struct.pack_into('<H', b, o + 0x1E, neg16(nvt_sum(bytes(b))))
    assert nvt_sum(bytes(b)) == 0
    path.write_bytes(b)
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    sub = ap.add_subparsers(dest='cmd', required=True)
    p = sub.add_parser('verify'); p.add_argument('image'); p.set_defaults(fn=cmd_verify)
    p = sub.add_parser('unpack'); p.add_argument('image'); p.add_argument('dir'); p.set_defaults(fn=cmd_unpack)
    p = sub.add_parser('pack'); p.add_argument('dir'); p.add_argument('out'); p.set_defaults(fn=cmd_pack)
    p = sub.add_parser('make'); p.add_argument('out'); p.add_argument('parts', nargs='+')
    p.set_defaults(fn=cmd_make)
    p = sub.add_parser('cksm'); p.add_argument('input'); p.add_argument('output')
    p.add_argument('--emb-type', type=lambda v: int(v, 0), default=0); p.set_defaults(fn=cmd_cksm)
    p = sub.add_parser('binsum'); p.add_argument('file')
    p.add_argument('--offset', type=lambda v: int(v, 0), default=0x350); p.set_defaults(fn=cmd_binsum)
    args = ap.parse_args()
    sys.exit(args.fn(args))


if __name__ == '__main__':
    main()
