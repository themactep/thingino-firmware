#!/bin/bash
# Build the OTA fitting test environment: a minimal x86_64 kernel with the
# MTD stack built in, a static busybox with the flash tools, and the
# initramfs the test VM boots.  Idempotent - skips whatever already exists.
#
# Artifacts land in ${THINGINO_OUTPUT_ROOT_DIR:-output}/ota-tests/.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
OUTROOT="${THINGINO_OUTPUT_ROOT_DIR:-$REPO/output}"
SCRATCH="$OUTROOT/ota-tests"

KERNEL_SRC="${KERNEL_SRC:-/usr/src/linux-source-6.19}"
KBUILD="$SCRATCH/kbuild"
BUSYBOX_TARBALL="${BUSYBOX_TARBALL:-$HOME/Files/thingino/dl/busybox/busybox-1.38.0.tar.bz2}"
BUSYBOX_SRC="$SCRATCH/busybox-1.38.0"
BB="$BUSYBOX_SRC/busybox"

echo "== OTA test build, scratch: $SCRATCH"

mkdir -p "$SCRATCH"

# --- kernel ---------------------------------------------------------------
if [ ! -f "$KBUILD/arch/x86/boot/bzImage" ]; then
	if [ ! -d "$KERNEL_SRC" ]; then
		echo "kernel source $KERNEL_SRC not found" >&2
		exit 1
	fi
	echo "== configuring minimal kernel"
	mkdir -p "$KBUILD"
	make -C "$KERNEL_SRC" O="$KBUILD" allnoconfig >/dev/null
	"$KERNEL_SRC/scripts/config" --file "$KBUILD/.config" \
		--enable 64BIT --enable X86_64 --disable X86_32 \
		--enable MULTIUSER --enable PRINTK --enable BUG --enable BINFMT_ELF --enable BINFMT_SCRIPT \
		--enable BLK_DEV_INITRD --enable RD_GZIP --enable TMPFS \
		--enable MISC_FILESYSTEMS --enable SQUASHFS \
		--enable DEVTMPFS --enable DEVTMPFS_MOUNT --enable PROC_FS --enable SYSFS \
		--enable PROC_SYSCTL --enable TTY \
		--enable SERIAL_8250 --enable SERIAL_8250_CONSOLE \
		--enable MTD --enable MTD_BLOCK --enable MTD_RAM \
		--enable MTD_CMDLINE_PARTS \
		--enable MODULES --module MTD_BLOCK2MTD \
		--enable PCI --enable VIRTIO_MENU --enable VIRTIO --enable VIRTIO_PCI \
		--enable VIRTIO_BLK --enable BLK_DEV
	make -C "$KERNEL_SRC" O="$KBUILD" olddefconfig >/dev/null
	echo "== building kernel (this takes a few minutes)"
	make -C "$KERNEL_SRC" O="$KBUILD" -j"$(nproc)" all >"$SCRATCH/kernel-build.log" 2>&1
	[ -f "$KBUILD/drivers/mtd/devices/block2mtd.ko" ] || {
		echo "block2mtd.ko not built" >&2
		exit 1
	}
else
	echo "== kernel already built"
fi

# --- busybox --------------------------------------------------------------
if [ ! -x "$BB" ]; then
	if [ ! -f "$BUSYBOX_TARBALL" ]; then
		echo "busybox tarball $BUSYBOX_TARBALL not found" >&2
		exit 1
	fi
	echo "== building busybox"
	tar xf "$BUSYBOX_TARBALL" -C "$SCRATCH"
	cd "$BUSYBOX_SRC"
	make defconfig >/dev/null
	sed -i 's/^# CONFIG_STATIC is not set/CONFIG_STATIC=y/; s/^# CONFIG_FLASH_ERASEALL is not set/CONFIG_FLASH_ERASEALL=y/; s/^# CONFIG_FLASHCP is not set/CONFIG_FLASHCP=y/' .config
	yes "" | make oldconfig >/dev/null
	make -j"$(nproc)" >"$SCRATCH/busybox-build.log" 2>&1
else
	echo "== busybox already built"
fi

# --- initramfs ------------------------------------------------------------
INITRD_DIR="$SCRATCH/initramfs"
echo "== assembling initramfs"
rm -rf "$INITRD_DIR"
mkdir -p "$INITRD_DIR"/{bin,sbin,lib,etc,proc,sys,dev,tmp,images}
cp "$BB" "$INITRD_DIR/bin/busybox"
"$BB" --install -s "$INITRD_DIR/bin"
# --install links applets to the build tree's absolute path; relink to busybox
for l in "$INITRD_DIR"/bin/*; do
	[ -L "$l" ] && ln -sf busybox "$l"
done
ln -sf /bin/busybox "$INITRD_DIR/sbin/poweroff"
ln -sf /bin/busybox "$INITRD_DIR/sbin/reboot"

# block2mtd module (loaded by init once /dev/vda exists).  The stock
# driver reports MTD_RAM, which libubootenv's fw_printenv rejects; report
# MTD_NORFLASH instead so the U-Boot env tools work on the emulated flash.
BLK2MTD_DIR="$SCRATCH/block2mtd-nor"
if [ ! -f "$BLK2MTD_DIR/block2mtd.ko" ]; then
	echo "== building patched block2mtd module"
	mkdir -p "$BLK2MTD_DIR"
	cp "$KERNEL_SRC/drivers/mtd/devices/block2mtd.c" "$BLK2MTD_DIR/"
	sed -i 's/dev->mtd.type = MTD_RAM;/dev->mtd.type = MTD_NORFLASH;/; s/dev->mtd.flags = MTD_CAP_RAM;/dev->mtd.flags = MTD_CAP_NORFLASH;/' "$BLK2MTD_DIR/block2mtd.c"
	printf 'obj-m := block2mtd.o\n' >"$BLK2MTD_DIR/Makefile"
	make -C "$KBUILD" M="$BLK2MTD_DIR" modules >"$SCRATCH/block2mtd-build.log" 2>&1
fi
cp "$BLK2MTD_DIR/block2mtd.ko" "$INITRD_DIR/block2mtd.ko"

# u-boot env tools (libubootenv) for the env partition access
if [ -f /usr/bin/fw_printenv ]; then
	cp /usr/bin/fw_printenv "$INITRD_DIR/sbin/fw_printenv"
	ln -sf fw_printenv "$INITRD_DIR/sbin/fw_setenv"
	for lib in $(ldd /usr/bin/fw_printenv | awk '/=>/ {print $3}'); do
		rel="${lib#/}"
		mkdir -p "$INITRD_DIR/$(dirname "$rel")"
		cp -L "$lib" "$INITRD_DIR/$rel"
	done
	mkdir -p "$INITRD_DIR/lib64"
	cp -L /lib64/ld-linux-x86-64.so.2 "$INITRD_DIR/lib64/"
fi

cp "$HERE/initramfs/init" "$INITRD_DIR/init"
chmod +x "$INITRD_DIR/init"
cp "$HERE/initramfs/fw_env.config" "$INITRD_DIR/etc/fw_env.config"
cp "$REPO/package/thingino-sysupgrade/files/flash-ota" "$INITRD_DIR/flash-ota.sh"
chmod +x "$INITRD_DIR/flash-ota.sh"

echo "== packing initramfs"
(cd "$INITRD_DIR" && find . -print0 | cpio --null -o -H newc 2>/dev/null | gzip -9) >"$SCRATCH/initramfs.cpio.gz"

# A tiny squashfs that pretends to be the old firmware rootfs: it carries the
# env tools so that, like on a real camera, fw_printenv/fw_setenv live on the
# rootfs partition that flash-ota erases. Baked into flash.img by the test
# runner and mounted by /init; the tools die with the partition.
FAKEROOT="$SCRATCH/fakeroot"
if [ ! -f "$SCRATCH/fakeroot.squashfs" ]; then
	echo "== building fakeroot squashfs"
	rm -rf "$FAKEROOT"
	mkdir -p "$FAKEROOT/sbin" "$FAKEROOT/etc"
	cp "$INITRD_DIR/sbin/fw_printenv" "$FAKEROOT/sbin/"
	ln -sf fw_printenv "$FAKEROOT/sbin/fw_setenv"
	cp "$HERE/initramfs/fw_env.config" "$FAKEROOT/etc/"
	mksquashfs "$FAKEROOT" "$SCRATCH/fakeroot.squashfs" -noappend -comp gzip >/dev/null
fi

echo "== done"
echo "kernel:   $KBUILD/arch/x86/boot/bzImage"
echo "initramfs: $SCRATCH/initramfs.cpio.gz"
