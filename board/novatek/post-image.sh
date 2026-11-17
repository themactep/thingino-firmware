#!/bin/sh
# Novatek images: the camera's DTB; FW<model>T.BIN (DTB + U-Boot), which the vendor loader boots
# from a card; sdcard.img for an SD install; autoupdate-full.bin (NAND from the fdt partition up) for a
# flash install; rootfs.img (the squashfs as a U-Boot ramdisk) for netboot.
set -e

BIN="$1"
cfg() { sed -n "s/^$1=\"\{0,1\}\([^\"]*\)\"\{0,1\}\$/\1/p" "$BR2_CONFIG"; }

MODEL=$(cfg BR2_NOVATEK_SOC_MODEL | tr '[:upper:]' '[:lower:]')
TBIN="FW${MODEL#nt}T.BIN"
DTS="$BR2_EXTERNAL_THINGINO_PATH/$CAMERA_SUBDIR/$CAMERA/$CAMERA.dts"
NVTPACK="python3 $BR2_EXTERNAL_THINGINO_PATH/scripts/nvtpack.py"

"$HOST_DIR/bin/dtc" -q -I dts -O dtb -o "$BIN/board.dtb" "$DTS"
"$HOST_DIR/bin/mkimage" -A arm -O linux -T ramdisk -C none -a 0 -e 0 -n thingino-rootfs \
	-d "$BIN/rootfs.squashfs" "$BIN/rootfs.img" >/dev/null

if [ -f "$BIN/u-boot.bin" ]; then
	$NVTPACK make "$BIN/$TBIN" 1:"$BIN/board.dtb" 3:"$BIN/u-boot.bin"
fi

if [ "$(cfg BR2_PACKAGE_NOVATEK_UBOOT_BOOT_SD)" = "y" ]; then
	cat >"$BIN/genimage-sd.cfg" <<-EOF
	image boot.vfat {
		vfat { files = { "$TBIN", "uImage", "board.dtb" } }
		size = 32M
	}
	image sdcard.img {
		hdimage {}
		partition boot { partition-type = 0xC image = "boot.vfat" offset = 1M }
		partition rootfs { partition-type = 0x83 image = "rootfs.ext2" }
	}
	EOF
	support/scripts/genimage.sh -c "$BIN/genimage-sd.cfg"
fi

if [ "$(cfg BR2_PACKAGE_NOVATEK_UBOOT_BOOT_NAND)" = "y" ]; then
	# Offsets from the DT's NAND map, relative to the fdt partition: the loader (first 256 KiB) is
	# never part of the image
	cat >"$BIN/ubinize.cfg" <<-EOF
	[kernel]
	mode=ubi
	vol_id=0
	vol_type=static
	vol_name=kernel
	image=$BIN/uImage
	[rootfs]
	mode=ubi
	vol_id=1
	vol_type=static
	vol_name=rootfs
	image=$BIN/rootfs.squashfs
	[overlay]
	mode=ubi
	vol_id=2
	vol_type=dynamic
	vol_name=overlay
	vol_size=1MiB
	vol_flags=autoresize
	EOF
	"$HOST_DIR/sbin/ubinize" -o "$BIN/ubi.img" -p 128KiB -m 2048 "$BIN/ubinize.cfg"

	AU="$BIN/autoupdate-full.bin"
	ff() { dd if=/dev/zero bs=1024 count=$(($1 / 1024)) 2>/dev/null | tr '\000' '\377'; }
	put() { dd if="$1" of="$AU" bs=1024 seek=$(($2 / 1024)) conv=notrunc 2>/dev/null; }
	ff 0x1a0000 >"$AU"
	put "$BIN/board.dtb" 0x0
	put "$BIN/u-boot.bin" 0x80000
	put "$BIN/ubi.img" 0x1a0000
	size=$(stat -c %s "$AU")
	ff $(((0x20000 - size % 0x20000) % 0x20000)) >>"$AU"
fi
