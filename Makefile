#
# OpenIPC Firmware
# themactep edition
# https://github.com/themactep/openipc-firmware
#

#CAMERA_IP_ADDRESS = $(shell read CAMERA_IP_ADDRESS)
CAMERA_IP_ADDRESS := "192.168.1.184"

BUILDROOT_VERSION = 2023.11

# overrides Buildroot dl/ directory
# can be reused from environment, just export the value:
# export BR2_DL_DIR = /path/to/your/local/storage
BR2_DL_DIR ?= $(HOME)/dl

# TFTP server IP address to upload compiled images to
TFTP_SERVER_IP ?= 192.168.1.254

# directory for extracting Buildroot sources
SRC_DIR ?= $(HOME)/src

BUILDROOT_BUNDLE := $(SRC_DIR)/buildroot-$(BUILDROOT_VERSION).tar.gz
BUILDROOT_DIR := $(SRC_DIR)/buildroot-$(BUILDROOT_VERSION)

# working directory
OUTPUT_DIR = $(HOME)/openipc-fw-output/$(BOARD)-br$(BUILDROOT_VERSION)

# OpenIPC project directories
SCRIPTS_DIR := $(CURDIR)/scripts
BUILDROOT_EXT_DIR := $(CURDIR)/general

# make command for buildroot
BR2_MAKE = $(MAKE) -C $(BUILDROOT_DIR) BR2_EXTERNAL=$(BUILDROOT_EXT_DIR) O=$(OUTPUT_DIR)

LIST_OF_BOARD = $(shell find ./br-ext-*/configs/*_defconfig | sort | sed -E "s/^\.\/br-ext-chip-(.+)\/configs\/(.*)_defconfig/'\2' '\1 \2'/")

# check BOARD value from env
ifeq ($(BOARD),)
# if empty, check for journal
ifeq ($(shell test -f .board; echo $$?),0)
# if found, restore BOARD from journal
BOARD := $(shell cat .board)
# ask permision to reuse the value
ifeq ($(shell whiptail --yesno "Use $(BOARD) from the previous session?" 10 40 3>&1 1>&2 2>&3; echo $$?),1)
# if told no, reset the BOARD
BOARD :=
# and remove the journal
$(shell rm .board)
endif
endif
endif

# if still no BOARD
ifeq ($(BOARD),)
# select it from a list of boards
BOARD := $(or $(shell whiptail --title "Available boards" --menu "Please select a board:" 20 76 12 --notags $(LIST_OF_BOARD) 3>&1 1>&2 2>&3),$(CONFIG))
endif

# if BOARD selected
ifneq ($(BOARD),)
# save selection to the journal
$(shell echo $(BOARD)>.board)
# find board config file
BOARD_CONFIG := $(shell find ./br-ext-*/configs/ -name $(BOARD)_defconfig)
endif

# did we find a config?
ifeq ($(BOARD_CONFIG),)
$(error Cannot find a config for the board: $(BOARD))
endif

# did we find multimple configs?
ifeq ($(echo $(BOARD_CONFIGS) | wc -w), 1)
$(error Found multiple configs for $(BOARD): $(BOARD_CONFIG))
endif

# include the config by its full path
DEFCONFIG := $(shell realpath $(BOARD_CONFIG))
include $(DEFCONFIG)

#SOC_VENDOR := $(patsubst "%",%,$(BR2_OPENIPC_SOC_VENDOR))
SOC_FAMILY := $(patsubst "%",%,$(BR2_OPENIPC_SOC_FAMILY))
SOC_MODEL := $(patsubst "%",%,$(BR2_OPENIPC_SOC_MODEL))

ifeq ($(BR2_OPENIPC_FLAVOR_LITE),y)
BR2_OPENIPC_FLAVOR := lite
else ifeq ($(BR2_OPENIPC_FLAVOR_FPV),y)
BR2_OPENIPC_FLAVOR := fpv
else ifeq ($(BR2_OPENIPC_FLAVOR_ULTIMATE),y)
BR2_OPENIPC_FLAVOR := ultimate
else
$(info Unknown flavor, using lite.)
BR2_OPENIPC_FLAVOR := lite
endif

KERNEL_VERSION := $(patsubst "%",%,$(BR2_LINUX_KERNEL_VERSION))
# BUILDROOT_EXT_DIR := $(CURDIR)/br-ext-chip-$(SOC_VENDOR)

ifneq ($(BR2_TOOLCHAIN_EXTERNAL),)
export BR2_TOOLCHAIN_EXTERNAL=y
OUTPUT_DIR := $(OUTPUT_DIR)-ext
endif

ifeq ($(BR2_OPENIPC_FLASH_SIZE_16M),y)
FLASH_SIZE_HEX := 0x1000000
FLASH_SIZE_MB := 16
FLASH_KERNEL_OFFSET_HEX := 0x50000
FLASH_ROOTFS_OFFSET_HEX := 0x350000
MAX_KERNEL_SIZE := $(shell printf "%d" 0x300000)
MAX_ROOTFS_SIZE := $(shell printf "%d" 0xA00000)
else ifeq ($(BR2_OPENIPC_FLASH_SIZE_8M),y)
FLASH_SIZE_HEX := 0x800000
FLASH_SIZE_MB := 8
FLASH_KERNEL_OFFSET_HEX := 0x50000
FLASH_ROOTFS_OFFSET_HEX := 0x250000
MAX_KERNEL_SIZE := $(shell printf "%d" 0x200000)
MAX_ROOTFS_SIZE := $(shell printf "%d" 0x500000)
else
$(error Flash size is not set in defconfig)
endif

# hardcoded variables
WGET := wget --quiet --no-verbose --retry-connrefused --continue --timeout=3
GITHUB_URL := https://github.com/OpenIPC/firmware/releases/download/latest
KERNEL_BIN := $(OUTPUT_DIR)/images/uImage
ROOTFS_BIN := $(OUTPUT_DIR)/images/rootfs.squashfs
ROOTFS_TAR := $(OUTPUT_DIR)/images/rootfs.tar
ROOTFS_CPIO := $(OUTPUT_DIR)/images/rootfs.cpio

FULL_FIRMWARE_NAME := openipc-$(SOC_MODEL)-$(BR2_OPENIPC_FLAVOR)-$(FLASH_SIZE_MB)mb.bin
FULL_FIRMWARE_BIN := $(OUTPUT_DIR)/images/$(FULL_FIRMWARE_NAME)
BOOTLOADER_BIN := $(OUTPUT_DIR)/images/u-boot-$(SOC_MODEL)-universal.bin

KERNEL_SIZE = $(shell stat -c%s $(KERNEL_BIN))
ROOTFS_SIZE = $(shell stat -c%s $(ROOTFS_BIN))

.PHONY: all toolchain sdk clean distclean br-% help pack tftp sdcard install-prerequisites overlayed-rootfs-%

all: $(OUTPUT_DIR)/.config
ifndef BOARD
	$(MAKE) BOARD=$(BOARD) $@
endif
	$(BR2_MAKE) all

# delete all build/{package} and per-package/{package} files
br-%-dirclean: $(OUTPUT_DIR)/.config
	rm -rvf $(OUTPUT_DIR)/per-package/$(subst -dirclean,,$(subst br-,,$@)) \
			$(OUTPUT_DIR)/build/$(subst -dirclean,,$(subst br-,,$@))*

br-%: $(OUTPUT_DIR)/.config
	$(BR2_MAKE) $(subst br-,,$@)

toolchain: $(OUTPUT_DIR)/.config
	$(BR2_MAKE) toolchain

sdk: $(OUTPUT_DIR)/.config
	$(BR2_MAKE) sdk

clean: $(OUTPUT_DIR)/.config
	$(BR2_MAKE) clean
	rm -rvf $(OUTPUT_DIR)/target $(OUTPUT_DIR)/.config

defconfig:
	$(BR2_MAKE) defconfig

distclean:
	# $(BOARD_MAKE) distclean
	if [ -d "$(OUTPUT_DIR)" ]; then rm -rf $(OUTPUT_DIR); fi

pack: $(FULL_FIRMWARE_BIN)
	@echo "DONE"

# upload kernel. rootfs and full image to tftp server
tftp: $(FULL_FIRMWARE_BIN)
	@busybox tftp -l $(KERNEL_BIN) -r uImage.$(SOC_FAMILY) -p $(TFTP_SERVER_IP)
	@busybox tftp -l $(ROOTFS_BIN) -r rootfs.squashfs.$(SOC_FAMILY) -p $(TFTP_SERVER_IP)
	@busybox tftp -l $(FULL_FIRMWARE_BIN) -r $(FULL_FIRMWARE_NAME) -p $(TFTP_SERVER_IP)

# upload full image to an sd card
sdcard: $(FULL_FIRMWARE_BIN)
	@cp -v $(KERNEL_BIN) $$(mount | grep sdc1 | awk '{print $$3}')
	@cp -v $(ROOTFS_BIN) $$(mount | grep sdc1 | awk '{print $$3}')
	@cp -v $(FULL_FIRMWARE_BIN) $$(mount | grep sdc1 | awk '{print $$3}')
	sync
	umount /dev/sdc1
	@echo "Done"

# upload kernel and rootfs in /tmp/ directory of the camera
upload:
	scp -O $(KERNEL_BIN) root@$(CAMERA_IP_ADDRESS):/tmp/uImage
	scp -O $(ROOTFS_BIN) root@$(CAMERA_IP_ADDRESS):/tmp/rootfs.squashfs

# upload firmware file on the camera via ssh and run upgrade remotely
upgrade: upload
	ssh root@$(CAMERA_IP_ADDRESS) "sysupgrade -z --kernel=/tmp/uImage --rootfs=/tmp/rootfs.squashfs --force_ver"

# install prerequisites
install-prerequisites:
ifneq ($(shell id -u), 0)
	$(error requested operation requires superuser privilege)
else
	@DEBIAN_FRONTEND=noninteractive apt-get update
	@DEBIAN_FRONTEND=noninteractive apt-get -y install build-essential bc bison cpio curl file flex git libncurses-dev make rsync unzip wget whiptail
endif

# prepare: $(OUTPUT_DIR)/.config $(BUILDROOT_DIR)/Makefile
#	@echo "Buildroot $(BUILDROOT_VERSION) is in $(BUILDROOT_DIR) directory."

# create output directory
$(OUTPUT_DIR):
	mkdir -p $(OUTPUT_DIR)

# check for toolchain parameters file
#$(OUTPUT_DIR)/toolchain-params.mk:
#	echo "$@ is not defined!"

# create source directory
$(SRC_DIR):
	mkdir -p $(SRC_DIR)

# install Buildroot sources
$(BUILDROOT_DIR)/.installed: $(BUILDROOT_BUNDLE)
	ls -l $(dirname $@)
	tar -C $(SRC_DIR) -xf $(BUILDROOT_BUNDLE)
	# remove shadowed packages
	# FIXME: it's a dirty hack because buildroot does not do overlaying
	# sed -i "/\/\(nginx\|wolfssl\)\//d" $(BUILDROOT_DIR)/package/Config.in
	# rm -r $(BUILDROOT_DIR)/package/nginx
	# rm -r $(BUILDROOT_DIR)/package/wolfssl
	# FIXME: It should not be needed but I tried to check for $(BUILDROOT_DIR)/Makefile and it keeps extracting the bundle again and again
	touch $@

# download Buildroot bundle
$(BUILDROOT_BUNDLE):
	$(WGET) -O $@ https://github.com/buildroot/buildroot/archive/refs/tags/$(BUILDROOT_VERSION).tar.gz
	#https://github.com/buildroot/buildroot/archive/refs/heads/master.zip

# create defconfig
$(OUTPUT_DIR)/.config: $(BUILDROOT_DIR)/.installed
	$(BR2_MAKE) BR2_DEFCONFIG=$(DEFCONFIG) defconfig

# download bootloader
# FIXME: should be built locally
$(BOOTLOADER_BIN):
	$(info BOOTLOADER_BIN: $@)
	$(WGET) -O $@ $(GITHUB_URL)/u-boot-$(SOC_MODEL)-universal.bin || \
	$(WGET) -O $@ $(GITHUB_URL)/u-boot-$(SOC_FAMILY)-universal.bin

# rebuild Linux kernel
$(KERNEL_BIN):
	$(info KERNEL_BIN: $@)
	$(BR2_MAKE) linux-rebuild
#	mv -vf $(OUTPUT_DIR)/images/uImage $@

# rebuild rootfs
$(ROOTFS_BIN):
	$(info ROOTFS_BIN: $@)
	$(BR2_MAKE) all
#	mv -vf $(OUTPUT_DIR)/images/rootfs.squashfs $@

# create .tar file of rootfs
$(ROOTFS_TAR):
	$(info ROOTFS_TAR: $@)
	$(BR2_MAKE) all
#	mv -vf $(OUTPUT_DIR)/images/rootfs.tar $@

# create .cpio file of rootfs
$(ROOTFS_CPIO):
	$(info ROOTFS_CPIO: $@)
	$(BR2_MAKE) all
#	mv -vf $(OUTPUT_DIR)/images/rootfs.cpio $@

# create a full firmware image
$(FULL_FIRMWARE_BIN) : $(BOOTLOADER_BIN) $(KERNEL_BIN) $(ROOTFS_BIN)
	$(info KERNEL_SIZE: $(KERNEL_SIZE))
	$(info MAX_KERNEL_SIZE: $(MAX_KERNEL_SIZE))
	$(info ROOTFS_SIZE: $(ROOTFS_SIZE))
	$(info MAX_ROOTFS_SIZE: $(MAX_ROOTFS_SIZE))
	$(info FLASH_SIZE_HEX: $(FLASH_SIZE_HEX))
	$(info BOOTLOADER_BIN: $(BOOTLOADER_BIN))
	$(info FULL_FIRMWARE_BIN: $@)
	@if [ "$(KERNEL_SIZE)" -gt "$(MAX_KERNEL_SIZE)" ]; then echo "Kernel size of $(KERNEL_SIZE) is larger than $(MAX_KERNEL_SIZE)"; exit 1; fi
	@if [ "$(ROOTFS_SIZE)" -gt "$(MAX_ROOTFS_SIZE)" ]; then echo "Rootfs size of $(ROOTFS_SIZE) is larger than $(MAX_ROOTFS_SIZE)"; exit 1; fi
	@dd if=/dev/zero bs=$$(($(FLASH_SIZE_HEX))) skip=0 count=1 status=none | tr '\000' '\377' > $(FULL_FIRMWARE_BIN)
	@dd if=$(BOOTLOADER_BIN) bs=$$(stat -c%s $(BOOTLOADER_BIN)) seek=0 count=1 of=$@ conv=notrunc status=none
	@dd if=$(KERNEL_BIN) bs=$(ROOTFS_SIZE) seek=$$(($(FLASH_KERNEL_OFFSET_HEX)))B count=1 of=$(FULL_FIRMWARE_BIN) conv=notrunc status=none
	@dd if=$(ROOTFS_BIN) bs=$(ROOTFS_SIZE) seek=$$(($(FLASH_ROOTFS_OFFSET_HEX)))B count=1 of=$(FULL_FIRMWARE_BIN) conv=notrunc status=none

### FIXME: B suffix works only with dd ver 9.0+
#	if [ $$(dd --version | head -1 | awk '{print $$3}' | cut -d. -f1) -lt 9 ]; then
#		dd if=$(KERNEL_BIN) bs=1 seek=$$(($(FLASH_KERNEL_OFFSET_HEX))) count=$(ROOTFS_SIZE) of=$(FULL_FIRMWARE_BIN) conv=notrunc status=none;
#		dd if=$(ROOTFS_BIN) bs=1 seek=$$(($(FLASH_ROOTFS_OFFSET_HEX))) count=$(ROOTFS_SIZE) of=$(FULL_FIRMWARE_BIN) conv=notrunc status=none;
#	fi

help:
	@echo "\n\
	BR-OpenIPC usage:\n\
	  - make help - print this help\n\
	  - make install-deps - install system deps\n\
	  - make BOARD=<BOARD-ID> all - build all needed for a board (toolchain, kernel and rootfs images)\n\
	  - make BOARD=<BOARD-ID> pack - create a full binary for programmer\n\
	  - make BOARD=<BOARD-ID> clean - cleaning before reassembly\n\
	  - make BOARD=<BOARD-ID> distclean - switching to the factory state\n\
	  - make BOARD=<BOARD-ID> prepare - download and unpack buildroot\n\
	  - make BOARD=<BOARD-ID> board-info - write to stdout information about selected board\n\
	  - make overlayed-rootfs-<FS-TYPE> ROOTFS_OVERLAYS=... - create rootfs image that contains original Buildroot target dir overlayed by some custom layers.\n\
	Example:\n\
	    make overlayed-rootfs-squashfs ROOTFS_OVERLAYS=./examples/echo_server/overlay\n\
	"

## there are some extra targets of specific packages
#include $(sort $(wildcard $(CURDIR)/extra/*.mk))


###### Buildroot directories
# TOPDIR             = ./buildroot
# STAGING_DIR        = ./output/staging
# TARGET_DIR         = ./output/target

# BASE_DIR           = ./output
# BASE_TARGET_DIR    = ./output/target
# BINARIES_DIR       = ./output/images
# HOST_DIR           = ./output/host
# HOST_DIR_SYMLINK   = ./output/host
# BUILD_DIR          = ./output/build
# LEGAL_INFO_DIR     = ./output/legal-info
# GRAPHS_DIR         = ./output/graphs
# PER_PACKAGE_DIR    = ./output/per-package
# CPE_UPDATES_DIR    = ./output/cpe-updates

#  <pkg>                         - Build and install <pkg> and all its dependencies
#  <pkg>-source                  - Only download the source files for <pkg>
#  <pkg>-extract                 - Extract <pkg> sources
#  <pkg>-patch                   - Apply patches to <pkg>
#  <pkg>-depends                 - Build <pkg>'s dependencies
#  <pkg>-configure               - Build <pkg> up to the configure step
#  <pkg>-build                   - Build <pkg> up to the build step
#  <pkg>-show-info               - Generate info about <pkg>, as a JSON blurb
#  <pkg>-show-depends            - List packages on which <pkg> depends
#  <pkg>-show-rdepends           - List packages which have <pkg> as a dependency
#  <pkg>-show-recursive-depends  - Recursively list packages on which <pkg> depends
#  <pkg>-show-recursive-rdepends - Recursively list packages which have <pkg> as a dependency
#  <pkg>-graph-depends           - Generate a graph of <pkg>'s dependencies
#  <pkg>-graph-rdepends          - Generate a graph of <pkg>'s reverse dependencies
#  <pkg>-dirclean                - Remove <pkg> build directory
#  <pkg>-reconfigure             - Restart the build from the configure step
#  <pkg>-rebuild                 - Restart the build from the build step
#  <pkg>-reinstall               - Restart the build from the install step
#  busybox-menuconfig            - Run BusyBox menuconfig
#  linux-menuconfig              - Run Linux kernel menuconfig
#  linux-savedefconfig           - Run Linux kernel savedefconfig
#  linux-update-defconfig        - Save the Linux configuration to the path specified by BR2_LINUX_KERNEL_CUSTOM_CONFIG_FILE
#  list-defconfigs               - list all defconfigs (pre-configured minimal systems)
#  source                        - download all sources needed for offline-build
#  external-deps                 - list external packages used
#  legal-info                    - generate info about license compliance
#  show-info                     - generate info about packages, as a JSON blurb
#  pkg-stats                     - generate info about packages as JSON and HTML
#  printvars                     - dump internal variables selected with VARS=...
#  make V=0|1                    - 0 => quiet build (default), 1 => verbose build
