#!/usr/bin/env python3
"""Patch vermagic in atbm6461_wifi_sdio.ko to match the build kernel.

Usage: patch_vermagic.py <src.ko> <dst.ko> <localver>

If the new vermagic fits in the original slot, an in-place replacement
with null padding is used.  If it is longer, the .modinfo ELF section
is expanded via objcopy --update-section.
"""
import sys, os, shutil, subprocess

src = sys.argv[1]
dst = sys.argv[2]
localver = sys.argv[3]
objcopy_cmd = sys.argv[4] if len(sys.argv) > 4 else 'objcopy'

old_v = b'3.10.14-Immortal preempt mod_unload MIPS32_R1 32BIT '
kern = '3.10.14' + localver
new_v = (kern + ' preempt mod_unload MIPS32_R1 32BIT ').encode()

data = bytearray(open(src, 'rb').read())
idx = data.find(old_v)
if idx < 0:
    sys.exit('ATBM6461: vermagic not found in .ko (pre-patched?)')

if len(new_v) <= len(old_v):
    # Fits in existing slot — in-place replace with null padding
    new_v_padded = new_v.ljust(len(old_v), b'\x00')
    data[idx:idx + len(old_v)] = new_v_padded
    open(dst, 'wb').write(bytes(data))
    print('ATBM6461: vermagic patched (in-place) -> ' + kern)
else:
    # Doesn't fit — expand .modinfo section via objcopy
    tmpdir = os.path.dirname(dst)
    mi_file = os.path.join(tmpdir, '_modinfo.bin')
    mi_new = os.path.join(tmpdir, '_modinfo_new.bin')

    # Extract .modinfo section as raw binary
    subprocess.run(
        [objcopy_cmd, '-O', 'binary', '--only-section=.modinfo', src, mi_file],
        check=True)

    # Replace the vermagic string in the extracted section data
    mi = bytearray(open(mi_file, 'rb').read())
    mi_idx = mi.find(old_v)
    if mi_idx < 0:
        sys.exit('ATBM6461: vermagic not found in .modinfo section')
    mi_new_data = mi[:mi_idx] + new_v + mi[mi_idx + len(old_v):]
    open(mi_new, 'wb').write(bytes(mi_new_data))

    # Copy original .ko and update the section
    shutil.copy(src, dst)
    subprocess.run(
        [objcopy_cmd, '--update-section', '.modinfo=' + mi_new, dst],
        check=True)

    # Clean up temporary files
    os.remove(mi_file)
    os.remove(mi_new)

    print('ATBM6461: vermagic patched (section expanded) -> ' + kern)
