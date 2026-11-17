#!/bin/sh
# Novatek images: the camera's DTB; FW<model>T.BIN (DTB + U-Boot), which the vendor loader boots
# from a card; sdcard.img for an SD install; rootfs.img (the squashfs as a U-Boot ramdisk) for netboot.
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
