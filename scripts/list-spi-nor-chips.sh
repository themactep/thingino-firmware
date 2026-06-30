#!/bin/bash
# list-spi-nor-chips.sh — Extract SPI NOR flash chip entries from a compiled U-Boot binary
#
# Usage: ./list-spi-nor-chips.sh [u-boot-with-spl-lzma.bin | u-boot.bin | ...]
#
# The script handles two cases:
#   1) SPL+LZMA image: finds the U-Boot IH_MAGIC header, extracts & decompresses
#      the LZMA payload, then searches the decompressed U-Boot for chip names.
#   2) Plain U-Boot ELF or raw binary: searches directly.
#
# Requires: 7z or lzma (command-line decompressor)

set -euo pipefail

UBOOT_BIN="${1:?Usage: $0 <u-boot-binary>}"
if [ ! -f "$UBOOT_BIN" ]; then
    echo "Error: file not found: $UBOOT_BIN" >&2
    exit 1
fi

TMPDIR=$(mktemp -d /tmp/uboot-spi-nor.XXXXXX)
trap 'rm -rf "$TMPDIR"' EXIT

# Chip-name prefixes recognised in the U-Boot jedec_spi_nor driver table
CHIP_PREFIXES='gd25 gm25 w25p w25q w25x w25h w25m mx25 en25 xt25 fm25 zb25 by25 s25fl n25q at25 m25p sst25 sst26 mt25 cr25 em25 xc25 pn25 p25q a25l kd25 nrg'

build_grep_pattern() {
    local first=true
    for p in $CHIP_PREFIXES; do
        if $first; then first=false; else printf '%s' '|'; fi
        printf '%s' "$p"
    done
}

PATTERN=$(build_grep_pattern)

search_binary() {
    local bin="$1"
    strings -n 4 "$bin" \
        | grep -iE "^($(build_grep_pattern))" \
        | sort -uf
}

# Check if the binary contains a U-Boot image header (IH_MAGIC = 0x27051956)
# and try to decompress the LZMA payload inside it.
try_decompress_uimage() {
    local bin="$1"

    # Find IH_MAGIC offset
    local magic_offset
    magic_offset=$(python3 -c "
import sys
data = open(sys.argv[1],'rb').read()
pos = data.find(b'\\x27\\x05\\x19\\x56')
if pos == -1:
    sys.exit(1)
print(pos)
" "$bin" 2>/dev/null) || return 1

    # Parse U-Boot image header (64 bytes)
    python3 -c "
import sys, struct, subprocess, os

data = open(sys.argv[1],'rb').read()
magic_offset = int(sys.argv[2])

hdr = data[magic_offset:magic_offset+64]
magic      = struct.unpack('>I', hdr[0:4])[0]
data_size  = struct.unpack('>I', hdr[12:16])[0]
comp_type  = hdr[31]
name       = hdr[33:33+32].split(b'\\x00')[0].decode('ascii','replace')

payload_offset = magic_offset + 64
payload = data[payload_offset:payload_offset+data_size]

lzma_path = os.path.join(sys.argv[3], 'uboot_payload.lzma')
out_path  = os.path.join(sys.argv[3], 'uboot_decompressed.bin')

with open(lzma_path, 'wb') as f:
    f.write(payload)

# Try 7z first, then lzma
result = subprocess.run(['7z', 'x', lzma_path, '-o' + sys.argv[3], '-y'],
                        capture_output=True)
if result.returncode == 0:
    # 7z extracts to the original filename; find it
    for root, dirs, files in os.walk(sys.argv[3]):
        for fn in files:
            fp = os.path.join(root, fn)
            if fp != lzma_path:
                os.rename(fp, out_path)
                print(out_path)
                sys.exit(0)

result = subprocess.run(['lzma', '-d', lzma_path, '-c'],
                        capture_output=True)
if result.returncode == 0:
    with open(out_path, 'wb') as f:
        f.write(result.stdout)
    print(out_path)
    sys.exit(0)

sys.exit(1)
" "$bin" "$magic_offset" "$TMPDIR" 2>/dev/null
}

# --- main logic ---

decompressed=$(try_decompress_uimage "$UBOOT_BIN" 2>/dev/null) || true

if [ -n "$decompressed" ] && [ -f "$decompressed" ]; then
    echo "# SPI NOR flash chips in U-Boot (decompressed from uImage LZMA payload):"
    search_binary "$decompressed"
else
    echo "# SPI NOR flash chips in $UBOOT_BIN (searching directly):"
    search_binary "$UBOOT_BIN"
fi
