#!/bin/bash
# shellcheck disable=SC2034
# SC2034: scenario functions set globals that run-tests.sh reads; each
# function only uses a subset, so every one looks "unused" in isolation.
# sysupgrade QEMU test scenarios.
#
# Each scenario sets:
#   NAME          test name
#   MODE          full | part
#   PART          boot | kernel | rootfs   (part only)
#   OLD_BOOT_K    boot partition size on the device (KiB)
#   NEW_BOOT_K    boot partition size in the new build (KiB)
#   OLD_ROOTFS_K  rootfs partition size on the device (KiB)
#   NEW_ROOTFS_K  rootfs image size in the new build (KiB)
#   DO_BACKUP     true | false             (full only)
#   EXPECT        flash | refuse | error
#   ERR_MSG       substring expected in the log for refuse/error
#
# env, backup, and kernel sizes are fixed at 64, 64, and 1600 KiB.  Data
# sizes are the remainder of the 8 MiB flash, computed by run-tests.sh.

scenario_full_same() {
	NAME=full-same
	MODE=full
	OLD_BOOT_K=192
	NEW_BOOT_K=192
	OLD_ROOTFS_K=5120
	NEW_ROOTFS_K=5120
	DO_BACKUP=true
	EXPECT=flash
}

scenario_full_shrink() {
	NAME=full-shrink
	MODE=full
	OLD_BOOT_K=320
	NEW_BOOT_K=192
	OLD_ROOTFS_K=5120
	NEW_ROOTFS_K=5120
	DO_BACKUP=true
	EXPECT=flash
}

scenario_full_grow() {
	NAME=full-grow
	MODE=full
	OLD_BOOT_K=192
	NEW_BOOT_K=320
	OLD_ROOTFS_K=5120
	NEW_ROOTFS_K=5120
	DO_BACKUP=true
	EXPECT=flash
}

scenario_full_shrink_nobackup() {
	NAME=full-shrink-nobackup
	MODE=full
	OLD_BOOT_K=320
	NEW_BOOT_K=192
	OLD_ROOTFS_K=5120
	NEW_ROOTFS_K=5120
	DO_BACKUP=false
	EXPECT=flash
}

scenario_part_boot_same() {
	NAME=part-boot-same
	MODE=part
	PART=boot
	OLD_BOOT_K=192
	NEW_BOOT_K=192
	OLD_ROOTFS_K=5120
	NEW_ROOTFS_K=5120
	DO_BACKUP=false
	EXPECT=flash
}

scenario_part_boot_shrink() {
	NAME=part-boot-shrink
	MODE=part
	PART=boot
	OLD_BOOT_K=320
	NEW_BOOT_K=192
	OLD_ROOTFS_K=5120
	NEW_ROOTFS_K=5120
	DO_BACKUP=false
	EXPECT=refuse
	ERR_MSG="env partition offset would change"
}

scenario_part_boot_grow() {
	NAME=part-boot-grow
	MODE=part
	PART=boot
	OLD_BOOT_K=192
	NEW_BOOT_K=320
	OLD_ROOTFS_K=5120
	NEW_ROOTFS_K=5120
	DO_BACKUP=false
	EXPECT=refuse
	ERR_MSG="env partition offset would change"
}

scenario_part_kernel_same() {
	NAME=part-kernel-same
	MODE=part
	PART=kernel
	OLD_BOOT_K=192
	NEW_BOOT_K=192
	OLD_ROOTFS_K=5120
	NEW_ROOTFS_K=5120
	DO_BACKUP=false
	EXPECT=flash
}

scenario_part_kernel_different() {
	NAME=part-kernel-different
	MODE=part
	PART=kernel
	OLD_BOOT_K=320
	NEW_BOOT_K=192
	OLD_ROOTFS_K=5120
	NEW_ROOTFS_K=5120
	DO_BACKUP=false
	EXPECT=flash
}

scenario_part_rootfs_same() {
	NAME=part-rootfs-same
	MODE=part
	PART=rootfs
	OLD_BOOT_K=192
	NEW_BOOT_K=192
	OLD_ROOTFS_K=5120
	NEW_ROOTFS_K=5120
	DO_BACKUP=false
	EXPECT=flash
}

scenario_part_rootfs_grow() {
	NAME=part-rootfs-grow
	MODE=part
	PART=rootfs
	OLD_BOOT_K=192
	NEW_BOOT_K=320
	OLD_ROOTFS_K=5120
	NEW_ROOTFS_K=5120
	DO_BACKUP=false
	EXPECT=flash
}

scenario_part_rootfs_shrink() {
	NAME=part-rootfs-shrink
	MODE=part
	PART=rootfs
	OLD_BOOT_K=320
	NEW_BOOT_K=192
	OLD_ROOTFS_K=5120
	NEW_ROOTFS_K=5120
	DO_BACKUP=false
	EXPECT=error
	ERR_MSG="exceed combined partitions"
}
