#!/bin/bash
# Build the sysupgrade QEMU test environment.  The kernel, static busybox,
# and patched block2mtd module come from scripts/ota-tests/build.sh; this
# script only assembles the initramfs with the real sysupgrade and flash-ota
# scripts.  Artifacts land in ${THINGINO_OUTPUT_ROOT_DIR:-output}/sysupgrade-tests/.
#
# Requirements are the same as scripts/ota-tests/build.sh (kernel source,
# busybox tarball, qemu, cpio, gzip).  KERNEL_SRC and BUSYBOX_TARBALL are
# forwarded to it.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
OUTROOT="${THINGINO_OUTPUT_ROOT_DIR:-$REPO/output}"
SCRATCH="$OUTROOT/sysupgrade-tests"
OTA="$OUTROOT/ota-tests"

echo "== sysupgrade test build, scratch: $SCRATCH"

# Reuse the shared QEMU kernel, busybox, and block2mtd build.
"$REPO/scripts/ota-tests/build.sh"

KERNEL="$OTA/kbuild/arch/x86/boot/bzImage"
BB=""
for b in "$OTA"/busybox-*/busybox; do
	if [ -x "$b" ]; then
		BB="$b"
		break
	fi
done
BLK="$OTA/block2mtd-nor/block2mtd.ko"

[ -f "$KERNEL" ] || {
	echo "kernel missing at $KERNEL" >&2
	exit 1
}
[ -n "$BB" ] && [ -x "$BB" ] || {
	echo "busybox missing under $OTA" >&2
	exit 1
}
[ -f "$BLK" ] || {
	echo "block2mtd.ko missing at $BLK" >&2
	exit 1
}

mkdir -p "$SCRATCH"
INITRD_DIR="$SCRATCH/initramfs"
rm -rf "$INITRD_DIR"
mkdir -p "$INITRD_DIR"/{bin,sbin,etc,proc,sys,dev,tmp}

cp "$BB" "$INITRD_DIR/bin/busybox"
"$BB" --install -s "$INITRD_DIR/bin"
for l in "$INITRD_DIR"/bin/*; do
	[ -L "$l" ] && ln -sf busybox "$l"
done
ln -sf /bin/busybox "$INITRD_DIR/sbin/reboot"
ln -sf /bin/busybox "$INITRD_DIR/sbin/poweroff"

cp "$BLK" "$INITRD_DIR/block2mtd.ko"

cp "$REPO/package/thingino-sysupgrade/files/sysupgrade" "$INITRD_DIR/sysupgrade"
cp "$REPO/package/thingino-sysupgrade/files/sysupgrade-stage2" "$INITRD_DIR/sysupgrade-stage2"
cp "$REPO/package/thingino-sysupgrade/files/flash-ota" "$INITRD_DIR/flash-ota"
chmod +x "$INITRD_DIR/sysupgrade" "$INITRD_DIR/sysupgrade-stage2" "$INITRD_DIR/flash-ota"

cp "$HERE/initramfs/init" "$INITRD_DIR/init"
chmod +x "$INITRD_DIR/init"

echo "== packing initramfs"
(cd "$INITRD_DIR" && find . -print0 | cpio --null -o -H newc 2>/dev/null | gzip -9) \
	>"$SCRATCH/initramfs.cpio.gz"

echo "== done"
echo "kernel:    $KERNEL"
echo "initramfs: $SCRATCH/initramfs.cpio.gz"
