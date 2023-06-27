#
# OpenIPC Firmware
#

# overrides Buildroot dl/ directory
BR2_DL_DIR := /home/paul/mnt/chulan/downloads_br

# TFTP server IP address to upload compiled images to
TFTP_SERVER_IP := 192.168.1.254

BUILDROOT_EXT_DIR := $(CURDIR)/br-ext-openipc

###### Buildroot directories
######
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

# OpenIPC project directories
SCRIPTS_DIR := $(CURDIR)/scripts

# directory for extracting Buildroot sources
# SRC_DIR := $(CURDIR)
SRC_DIR := $(HOME)/local/src

# working directory
OUTPUT_DIR := $(shell realpath $(CURDIR)/../openipc-output)

ifndef BOARD
BOARD := $(shell whiptail --title "Available boards" --menu "Please select a board:" 20 76 12 --notags $(shell find ./br-ext-chip-*/configs/ -type f -name "*_defconfig" | sort | sed -E "s/^\.\/br-ext-chip-(.+)\/configs\/(.*)_defconfig/'\2' '\1 \2'/") 3>&1 1>&2 2>&3)
endif

DEFCONFIGS := $(shell find ./br-ext-*/configs/ -name $(BOARD)_defconfig)
ifeq ($(DEFCONFIGS),)
	$(error Cannot find a config for $(BOARD))
else ifeq ($(echo $(DEFCONFIGS) | wc -w), 1)
	$(error Found multiple configs for $(BOARD): $(DEFCONFIGS))
else
DEFCONFIG := $(shell realpath $(DEFCONFIGS))
endif
include $(DEFCONFIG)
$(eval SOC_VENDOR = $(patsubst "%",%,$(BR2_OPENIPC_SOC_VENDOR)))
$(eval SOC_FAMILY = $(patsubst "%",%,$(BR2_OPENIPC_SOC_FAMILY)))
$(eval SOC_MODEL = $(patsubst "%",%,$(BR2_OPENIPC_SOC_MODEL)))
$(eval BUILDROOT_VERSION = $(patsubst "%",%,$(BR2_OPENIPC_BR_VERSION)))
$(eval KERNEL_VERSION = $(patsubst "%",%,$(BR2_LINUX_KERNEL_VERSION)))
$(eval BUILDROOT_EXT_DIR = $(CURDIR)/br-ext-chip-$(SOC_VENDOR))
$(eval BUILDROOT_DIR = $(SRC_DIR)/buildroot-$(BUILDROOT_VERSION))
$(eval OUTPUT_DIR = $(OUTPUT_DIR)/$(BOARD)-br$(BUILDROOT_VERSION))
ifneq ($(BR2_TOOLCHAIN_EXTERNAL),)
export BR2_TOOLCHAIN_EXTERNAL=y
$(eval OUTPUT_DIR = $(OUTPUT_DIR)-ext)
endif
$(eval BOARD_MAKE = $(MAKE) -C $(BUILDROOT_DIR) O=$(OUTPUT_DIR) BR2_EXTERNAL=$(BUILDROOT_EXT_DIR))
ifeq ($(BR2_OPENIPC_FLAVOR_LITE),y)
$(eval FW_FLAVOR = lite)
else ifeq ($(BR2_OPENIPC_FLAVOR_FPV),y)
$(eval FW_FLAVOR = fpv)
else ifeq ($(BR2_OPENIPC_FLAVOR_ULTIMATE),y)
$(eval FW_FLAVOR = ultimate)
else
$(error Unknown flavor)
endif
ifeq ($(BR2_OPENIPC_FLASH_SIZE_8M),y)
$(eval FLASH_SIZE_HEX = 0x800000)
$(eval FLASH_SIZE_MB = 8)
$(eval FLASH_KERNEL_OFFSET_HEX = 0x50000)
$(eval FLASH_ROOTFS_OFFSET_HEX = 0x250000)
$(eval MAX_KERNEL_SIZE = $(shell printf "%d" 0x200000))
$(eval MAX_ROOTFS_SIZE = $(shell printf "%d" 0x500000))
else ifeq ($(BR2_OPENIPC_FLASH_SIZE_16M),y)
$(eval FLASH_SIZE_HEX = 0x1000000)
$(eval FLASH_SIZE_MB = 16)
$(eval FLASH_KERNEL_OFFSET_HEX = 0x50000)
$(eval FLASH_ROOTFS_OFFSET_HEX = 0x350000)
$(eval MAX_KERNEL_SIZE = $(shell printf "%d" 0x300000))
$(eval MAX_ROOTFS_SIZE = $(shell printf "%d" 0xA00000))
endif

WGET = wget --quiet --no-verbose --retry-connrefused --continue --timeout=3

GITHUB_URL         = https://github.com/OpenIPC/firmware/releases/download/latest
BUILDROOT_BUNDLE   = $(SRC_DIR)/buildroot-$(BUILDROOT_VERSION).tar.gz
BUILDROOT_DIR      = $(SRC_DIR)/buildroot-$(BUILDROOT_VERSION)
FULL_FIRMWARE_NAME = openipc-$(SOC_MODEL)-$(FW_FLAVOR)-$(FLASH_SIZE_MB)mb.bin
FULL_FIRMWARE_BIN  = $(OUTPUT_DIR)/images/$(FULL_FIRMWARE_NAME)
BOOTLOADER_BIN     = $(OUTPUT_DIR)/images/u-boot-$(SOC_MODEL)-universal.bin

KERNEL_BIN         = $(OUTPUT_DIR)/images/uImage              #.$(SOC_MODEL)
ROOTFS_BIN         = $(OUTPUT_DIR)/images/rootfs.squashfs     #.$(SOC_MODEL)
ROOTFS_TAR         = $(OUTPUT_DIR)/images/rootfs.tar
ROOTFS_CPIO        = $(OUTPUT_DIR)/images/rootfs.cpio

.PHONY: all toolchain sdk clean distclean br-% help pack tftp sdcard install-prerequisites overlayed-rootfs-%

###### tasks handled by Buildroot
###### these should be delegated to Buildroot rather than rewritten
all: $(OUTPUT_DIR)/.config
ifndef BOARD
	$(MAKE) BOARD=$(BOARD) $@
endif
	$(BOARD_MAKE) all

toolchain: $(OUTPUT_DIR)/.config
	$(BOARD_MAKE) toolchain

sdk: $(OUTPUT_DIR)/.config
	$(BOARD_MAKE) sdk

clean: $(OUTPUT_DIR)/.config
	$(BOARD_MAKE) clean
	rm -rvf $(OUTPUT_DIR)/target $(OUTPUT_DIR)/.config

defconfig:
	$(BOARD_MAKE) defconfig

distclean:
	# $(BOARD_MAKE) distclean
	if [ -d "$(OUTPUT_DIR)" ]; then rm -rf $(OUTPUT_DIR); fi

###### anything prefixed with br-
br-%: $(OUTPUT_DIR)/.config
	$(BOARD_MAKE) $(subst br-,,$@)

pack: $(FULL_FIRMWARE_BIN)
	@echo "DONE"

tftp: $(FULL_FIRMWARE_BIN)
	@busybox tftp -l $(KERNEL_BIN) -r uImage.$(SOC_MODEL) -p $(TFTP_SERVER_IP)
	@busybox tftp -l $(ROOTFS_BIN) -r rootfs.squashfs.$(SOC_MODEL) -p $(TFTP_SERVER_IP)
	@busybox tftp -l $(FULL_FIRMWARE_BIN) -r $(FULL_FIRMWARE_NAME) -p $(TFTP_SERVER_IP)

sdcard: $(FULL_FIRMWARE_BIN)
	#@cp $(FULL_FIRMWARE_BIN) $$(mount | grep sdb1 | awk '{print $$3}')/$(FULL_FIRMWARE_NAME)
	#sync
	#umount /dev/sdb1
	#umount /dev/sdb2
	#@echo "Done"

install-prerequisites:
	ifneq ($(shell id -u), 0)
		$(error You must be root to perform this action.)
	else
		@DEBIAN_FRONTEND=noninteractive apt-get update
		@DEBIAN_FRONTEND=noninteractive apt-get -y install build-essential bc bison cpio curl file flex git libncurses-dev make rsync unzip wget whiptail
	endif

# prepare: $(OUTPUT_DIR)/.config $(BUILDROOT_DIR)/Makefile
#	@echo "Buildroot $(BUILDROOT_VERSION) is in $(BUILDROOT_DIR) directory."

$(OUTPUT_DIR):
	mkdir -p $(OUTPUT_DIR)

$(OUTPUT_DIR)/.config: $(BUILDROOT_DIR)/Makefile
	$(BOARD_MAKE) BR2_DEFCONFIG=$(DEFCONFIG) defconfig

#$(OUTPUT_DIR)/toolchain-params.mk:
#	echo "$(OUTPUT_DIR)/toolchain-params.mk is not defined!"

$(SRC_DIR):
	mkdir -p $(SRC_DIR)

$(BUILDROOT_DIR)/Makefile: $(BUILDROOT_BUNDLE)
	tar -C $(SRC_DIR) -xf $(BUILDROOT_BUNDLE)

$(BUILDROOT_BUNDLE):
	$(WGET) -O $@ https://buildroot.org/downloads/buildroot-$(BUILDROOT_VERSION).tar.gz || \
	$(WGET) -O $@ https://github.com/buildroot/buildroot/archive/refs/tags/$(BUILDROOT_VERSION).tar.gz
	#https://github.com/buildroot/buildroot/archive/refs/heads/master.zip

$(KERNEL_BIN):
	$(info KERNEL_BIN: $@)
	$(BOARD_MAKE) linux-rebuild
#	mv -vf $(OUTPUT_DIR)/images/uImage $@

$(ROOTFS_BIN):
	$(info ROOTFS_BIN: $@)
	$(BOARD_MAKE) all
#	mv -vf $(OUTPUT_DIR)/images/rootfs.squashfs $@

$(ROOTFS_TAR):
	$(info ROOTFS_TAR: $@)
	$(BOARD_MAKE) all
#	mv -vf $(OUTPUT_DIR)/images/rootfs.tar $@

$(ROOTFS_CPIO):
	$(info ROOTFS_CPIO: $@)
	$(BOARD_MAKE) all
#	mv -vf $(OUTPUT_DIR)/images/rootfs.cpio $@

$(BOOTLOADER_BIN):
	$(info BOOTLOADER_BIN: $@)
	$(WGET) -O $@ $(GITHUB_URL)/u-boot-$(SOC_MODEL)-universal.bin || \
	$(WGET) -O $@ $(GITHUB_URL)/u-boot-$(SOC_FAMILY)-universal.bin

KERNEL_SIZE = $(shell stat -c%s $(KERNEL_BIN))
ROOTFS_SIZE = $(shell stat -c%s $(ROOTFS_BIN))

$(FULL_FIRMWARE_BIN) : $(BOOTLOADER_BIN) $(KERNEL_BIN) $(ROOTFS_BIN)
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

#buildroot-version: config
#	@echo $(BUILDROOT_VERSION)

#firmware-flavor: config
#	@echo $(FW_FLAVOR)

#board-info: config
#	@cat $(BUILDROOT_EXT_DIR)/board/$(SOC_FAMILY)/config | grep RAM_LINUX_SIZE
#	@cat $(BUILDROOT_EXT_DIR)/board/$(SOC_FAMILY)/$(SOC_MODEL).config
#	@cat $(BUILDROOT_EXT_DIR)/board/$(SOC_FAMILY)/config

#has-nand: config
#	ifeq ($(BR2_TARGET_ROOTFS_UBI),y)
#		@echo "y"
#	else
#		@echo "n"
#	endif

# FIXME: this one is broken
#toolname: config
#	@$(SCRIPTS_DIR)/show_toolchains.sh $(DEFCONFIG) $(BUILDROOT_VERSION)

## -------------------------------------------------------------------------------------------------
## TODO: Elaborate how to compile wireguard-linux-compat under GCC 12 without this patch
## FIXME: wireguard-linux-compat patch is needed only for kernel older than 5.4, and since kernel 5.6 WireGuard is in the kernel.
##  $(KERNEL_VERSION)
##define remove-patches
##	$(if $(filter $(BUILDROOT_VERSION),2020.02.12 2021.02.12),-rm general/package/all-patches/wireguard-linux-compat/remove_fallthrough.patch)
##endef
## -------------------------------------------------------------------------------------------------
## create rootfs image that contains original Buildroot target dir overlayed by some custom layers
## space-separated list of overlays
#
#ROOTFS_OVERLAYS ?=
## overlayed rootfs directory
#ROOTFS_OVERLAYED_DIR ?= $(OUTPUT_DIR)/target-overlayed
## overlayed rootfs image's name (without prefix)
#ROOTFS_OVERLAYED_IMAGE ?= rootfs-overlayed
#
#overlayed-rootfs-%: $(OUTPUT_DIR)/.config
#	$(SCRIPTS_DIR)/create_overlayed_rootfs.sh $(ROOTFS_OVERLAYED_DIR) $(OUTPUT_DIR)/target $(ROOTFS_OVERLAYS)
#	$(BOARD_MAKE) $(subst overlayed-,,$@) \
#	    BASE_TARGET_DIR=$(abspath $(ROOTFS_OVERLAYED_DIR)) \
#	    ROOTFS_$(call UPPERCASE,$(subst overlayed-rootfs-,,$@))_FINAL_IMAGE_NAME=$(ROOTFS_OVERLAYED_IMAGE).$(subst overlayed-rootfs-,,$@)
## -------------------------------------------------------------------------------------------------
#%_info:
#	@echo
#	@cat $(BUILDROOT_EXT_DIR)/board/$(subst _info,,$@)/config | grep RAM_LINUX_SIZE
#	#$(eval SOC_VENDOR 	:= $(shell echo $@ | cut -d "_" -f 1))
#	#$(eval SOC_FAMILY 	:= $(shell cat $(BUILDROOT_EXT_DIR)/board/$(subst _info,,$@)/config | grep FAMILY | cut -d "=" -f 2))
#	#$(eval SOC_MODEL	:= $(shell echo $@ | cut -d "_" -f 3))
#	@cat $(BUILDROOT_EXT_DIR)/board/$(SOC_FAMILY)/$(SOC_MODEL).config
## -------------------------------------------------------------------------------------------------

#HEX2DEC   = $(shell printf "%d" 0x$(1))
#UPPERCASE = $(shell echo $(1) | tr a-z A-Z)

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
