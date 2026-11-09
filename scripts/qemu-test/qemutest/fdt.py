"""Device trees in a flash image. The 4.4 kernels carry their board's
wiring in one, so stock firmware says there what thingino.json would."""

import bz2
import gzip
import lzma
import struct
import zlib

UIMAGE = b"\x27\x05\x19\x56"
FDT = b"\xd0\x0d\xfe\xed"


def _unpack(data, comp):
    """A kernel decompressed by its uImage type or FIT name; b"" when it
    is not one of these."""
    try:
        if comp in (0, "none"):
            return data
        if comp in (1, "gzip"):
            return gzip.decompress(data)
        if comp in (2, "bzip2"):
            return bz2.decompress(data)
        if comp in (3, "lzma"):
            return lzma.LZMADecompressor(
                format=lzma.FORMAT_ALONE).decompress(data)
    except (OSError, EOFError, ValueError, lzma.LZMAError, zlib.error):
        pass
    return b""


def _nodes(blob):
    """[(path, {property: bytes})] of a flattened device tree."""
    if len(blob) < 40 or blob[:4] != FDT:
        return []
    total, struct_off, strings_off = struct.unpack(">III", blob[4:16])
    path, props, out = [], [], []
    pos = struct_off
    try:
        while pos + 4 <= total:
            token = struct.unpack(">I", blob[pos:pos + 4])[0]
            pos += 4
            if token == 1:                      # FDT_BEGIN_NODE
                end = blob.index(b"\0", pos)
                path.append(blob[pos:end].decode("latin-1"))
                props.append({})
                out.append(("/".join(path), props[-1]))
                pos = (end + 4) & ~3
            elif token == 3:                    # FDT_PROP
                size, name = struct.unpack(">II", blob[pos:pos + 8])
                name += strings_off
                key = blob[name:blob.index(b"\0", name)].decode("latin-1")
                props[-1][key] = blob[pos + 8:pos + 8 + size]
                pos = (pos + 8 + size + 3) & ~3
            elif token == 2:                    # FDT_END_NODE
                path.pop()
                props.pop()
            elif token != 4:                    # FDT_NOP, else the end
                break
    except (ValueError, IndexError, struct.error):
        pass
    return out


def _trees(data, depth=0):
    """Every device tree in data, and in the uImage and FIT kernels there
    (a kernel built with its tree has it inside, compressed)."""
    trees = []
    i = data.find(FDT)
    while i >= 0:
        total = struct.unpack(">I", data[i + 4:i + 8].ljust(4, b"\0"))[0]
        nodes = _nodes(data[i:i + total])
        if nodes:
            trees.append(nodes)
            for path, props in nodes:
                if depth < 2 and "/images/" in path and "data" in props:
                    comp = props.get("compression", b"none\0")
                    trees += _trees(_unpack(props["data"],
                                            comp.rstrip(b"\0").decode()),
                                    depth + 1)
        i = data.find(FDT, i + 4)
    i = data.find(UIMAGE)
    while i >= 0 and depth < 2:
        head = data[i:i + 64]
        if len(head) == 64 and zlib.crc32(head[:4] + bytes(4) + head[8:]) \
                == struct.unpack(">I", head[4:8])[0]:
            size = struct.unpack(">I", head[12:16])[0]
            trees += _trees(_unpack(data[i + 64:i + 64 + size], head[31]),
                            depth + 1)
        i = data.find(UIMAGE, i + 4)
    return trees


def msc0_card_detect(image):
    """(port, pin, active_low) of the card-detect GPIO that the image's
    device tree gives MSC0, or None. The vendor 4.4 kernels read it from
    ingenic,cd-gpios, active low when the flags cell says so."""
    with open(image, "rb") as f:
        data = f.read()
    for nodes in _trees(data):
        banks = {}
        for path, props in nodes:
            handle = props.get("phandle") or props.get("linux,phandle")
            if handle and len(handle) == 4:
                banks[struct.unpack(">I", handle)[0]] = path.split("/")[-1]
        for path, props in nodes:
            if not path.split("/")[-1].startswith(("msc@0x13060000",
                                                   "msc@13060000",
                                                   "mmc@13060000")):
                continue
            cells = props.get("ingenic,cd-gpios") or props.get("cd-gpios")
            if not cells or len(cells) < 12:
                continue
            handle, pin, flags = struct.unpack(">III", cells[:12])
            bank = banks.get(handle, "")
            if len(bank) == 3 and bank[:2] == "gp" and bank[2] in "abcdef" \
                    and pin < 32:
                return ord(bank[2]) - ord("a"), pin, bool(flags & 1)
    return None
