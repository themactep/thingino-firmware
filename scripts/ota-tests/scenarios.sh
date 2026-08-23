#!/bin/bash
# shellcheck disable=SC2034
# SC2034: scenario functions set globals that run-tests.sh reads; each
# function only uses a subset, so every one looks "unused" in isolation.
# OTA fitting test scenarios.
#
# Each scenario function sets:
#   NAME          test name
#   OLD_MTDPARTS  the layout on the "device" (kernel cmdline + U-Boot env)
#   MODE          flash-ota mode: rootfs | kernel | boot
#   ROOTFS_K      new rootfs image size in KiB (0 = absent)
#   DATA_K        new data image size in KiB (0 = absent)
#   KERNEL_K      new kernel image size in KiB (kernel mode)
#   BOOT_K        new boot image size in KiB (boot mode)
#   ENV_K         new env image size in KiB (boot mode; 0 = use real env blob)
#   FILL / FILLD  rootfs / data fill byte (hex)
#   EXPECT        flash | error
#   ERR_MSG       substring expected in the flash-ota output for EXPECT=error
#   RESERVED_K    extra "reserved" partition size in KiB between rootfs and
#                 data (non-adjacent layout)
#   REAL_IMAGES   non-empty to bake real images from IMG_DIR into the VM

BASE='block2mtd:256k(boot),64k(env),64k(backup),1600k(kernel)'
ALL_TAIL=',8192k@0(all)'

scenario_fit_normal() {
	NAME=fit-normal
	OLD_MTDPARTS="$BASE,5120k(rootfs),1088k(data)$ALL_TAIL"
	MODE=rootfs
	ROOTFS_K=4608
	DATA_K=640
	FILL=aa
	FILLD=55
	EXPECT=flash
	ERR_MSG=
}

scenario_exact_fit() {
	NAME=exact-fit
	OLD_MTDPARTS="$BASE,5760k(rootfs),448k(data)$ALL_TAIL"
	MODE=rootfs
	ROOTFS_K=5760
	DATA_K=448
	FILL=aa
	FILLD=55
	EXPECT=flash
	ERR_MSG=
}

scenario_rootfs_grew() {
	NAME=rootfs-grew
	OLD_MTDPARTS="$BASE,5568k(rootfs),640k(data)$ALL_TAIL"
	MODE=rootfs
	ROOTFS_K=5760
	DATA_K=448
	FILL=aa
	FILLD=55
	EXPECT=flash
	ERR_MSG=
}

scenario_rootfs_shrunk() {
	NAME=rootfs-shrunk
	OLD_MTDPARTS="$BASE,5760k(rootfs),448k(data)$ALL_TAIL"
	MODE=rootfs
	ROOTFS_K=5120
	DATA_K=1088
	FILL=aa
	FILLD=55
	EXPECT=flash
	ERR_MSG=
}

scenario_rootfs_only() {
	NAME=rootfs-only
	OLD_MTDPARTS="$BASE,5568k(rootfs),640k(data)$ALL_TAIL"
	MODE=rootfs
	ROOTFS_K=5760
	DATA_K=0
	FILL=aa
	FILLD=55
	EXPECT=flash
	ERR_MSG=
}

scenario_too_big() {
	NAME=too-big
	OLD_MTDPARTS="$BASE,5568k(rootfs),640k(data)$ALL_TAIL"
	MODE=rootfs
	ROOTFS_K=5760
	DATA_K=1024
	FILL=aa
	FILLD=55
	EXPECT=error
	ERR_MSG='exceed combined partitions'
}

scenario_no_all() {
	NAME=no-all
	OLD_MTDPARTS="$BASE,5568k(rootfs),640k(data)"
	MODE=rootfs
	ROOTFS_K=5760
	DATA_K=448
	FILL=aa
	FILLD=55
	EXPECT=error
	ERR_MSG="no 'all' partition"
}

scenario_non_adjacent() {
	NAME=non-adjacent
	OLD_MTDPARTS="$BASE,5120k(rootfs),64k(reserved),1024k(data)$ALL_TAIL"
	MODE=rootfs
	ROOTFS_K=5504
	DATA_K=512
	FILL=aa
	FILLD=55
	RESERVED_K=64
	EXPECT=error
	ERR_MSG='not adjacent'
}

scenario_kernel() {
	NAME=kernel
	OLD_MTDPARTS="$BASE,5568k(rootfs),640k(data)$ALL_TAIL"
	MODE=kernel
	KERNEL_K=1600
	EXPECT=normal
	ERR_MSG=
}

scenario_kernel_real() {
	NAME=kernel-real
	OLD_MTDPARTS="$BASE,5568k(rootfs),640k(data)$ALL_TAIL"
	MODE=kernel
	KERNEL_K=0
	REAL_IMAGES=1
	EXPECT=normal
	ERR_MSG=
}

scenario_boot() {
	NAME=boot
	OLD_MTDPARTS="$BASE,5568k(rootfs),640k(data)$ALL_TAIL"
	MODE=boot
	BOOT_K=0
	ENV_K=0
	REAL_IMAGES=1
	EXPECT=normal
	ERR_MSG=
}

scenario_real_images() {
	NAME=real-images
	OLD_MTDPARTS="$BASE,5568k(rootfs),640k(data)$ALL_TAIL"
	MODE=rootfs
	ROOTFS_K=0
	DATA_K=0
	FILL=aa
	FILLD=55
	REAL_IMAGES=1
	EXPECT=flash
	ERR_MSG=
}
