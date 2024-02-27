# Thingino Firmware
# https://github.com/themactep/thingino-firmware

BUILDROOT_VERSION := git

# Camera IP address
CAMERA_IP_ADDRESS ?= 192.168.1.10

# Device of SD card
SDCARD_DEVICE ?= /dev/sdc

# TFTP server IP address to upload compiled images to
TFTP_IP_ADDRESS ?= 192.168.1.254

# Buildroot downloads directory
# can be reused from environment, just export the value:
# export BR2_DL_DIR = /path/to/your/local/storage
BR2_DL_DIR ?= $(HOME)/dl

# directory for extracting Buildroot sources
SRC_DIR ?= $(HOME)/src

# working directory
OUTPUT_DIR ?= $(HOME)/output/$(BOARD)
STDOUT_LOG ?= $(OUTPUT_DIR)/compilation.log
STDERR_LOG ?= $(OUTPUT_DIR)/compilation-errors.log

BUILDROOT_BUNDLE := $(SRC_DIR)/buildroot-$(BUILDROOT_VERSION).tar.gz
BUILDROOT_REPO := https://github.com/themactep/buildroot.git
BUILDROOT_DIR := $(SRC_DIR)/buildroot-$(BUILDROOT_VERSION)-themactep

# project directories
BR2_EXTERNAL := $(CURDIR)
SCRIPTS_DIR := $(CURDIR)/scripts

# make command for buildroot
BR2_MAKE = $(MAKE) -C $(BUILDROOT_DIR) BR2_EXTERNAL=$(BR2_EXTERNAL) O=$(OUTPUT_DIR)

BOARDS = $(shell find ./configs/*_defconfig | grep -v "\(_generic\|toolchain_\)" | sort | sed -E "s/^\.\/configs\/(.*)_defconfig/'\1' '\1'/")

# check BOARD value from env
# if empty, check for journal
# if found, restore BOARD from journal, ask permision to reuse the value.
# if told no, reset the BOARD and remove the journal
ifeq ($(BOARD),)
ifeq ($(shell test -f .board; echo $$?),0)
BOARD = $(shell cat .board)
ifeq ($(shell whiptail --yesno "Use $(BOARD) from the previous session?" 10 40 3>&1 1>&2 2>&3; echo $$?),1)
BOARD =
endif
endif
endif

# if still no BOARD, select it from a list of boards
ifeq ($(BOARD),)
BOARD := $(or $(shell whiptail --title "Boards" --menu "Select a board:" 20 76 12 --notags $(BOARDS) 3>&1 1>&2 2>&3))
endif

# if still no BOARD, bail out with an error
ifeq ($(BOARD),)
$(error NO BOARD!)
endif

# otherwise, save selection to the journal
$(shell echo $(BOARD)>.board)

# find board config file
BOARD_CONFIG = $(shell find $(BR2_EXTERNAL)/configs/ -name $(BOARD)_defconfig)

# if board config file not found, bail out with an error
ifeq ($(BOARD_CONFIG),)
$(error Cannot find a config for the board: $(BOARD))
endif

# if multimple config files are found, bail out with an error
ifeq ($(echo $(BOARD_CONFIGS) | wc -w), 1)
$(error Found multiple configs for $(BOARD): $(BOARD_CONFIG))
endif

# read common config file
include $(BR2_EXTERNAL)/common.mk

# read camera config file
include $(BOARD_CONFIG)

# include device tree makefile
include $(BR2_EXTERNAL)/external.mk

# hardcoded variables
WGET := wget --quiet --no-verbose --retry-connrefused --continue --timeout=3

U_BOOT_GITHUB_URL := https://github.com/gtxaspec/u-boot-ingenic/releases/download/latest
U_BOOT_BIN  = $(OUTPUT_DIR)/images/u-boot-$(SOC_MODEL_LESS_Z).bin
KERNEL_BIN := $(OUTPUT_DIR)/images/uImage
ROOTFS_BIN := $(OUTPUT_DIR)/images/rootfs.squashfs
ROOTFS_TAR := $(OUTPUT_DIR)/images/rootfs.tar

# create a full binary file suffixed with the time of the last modification to either uboot, kernel, or rootfs
FIRMWARE_NAME_FULL = thingino-$(BOARD)-$(shell \
    U_BOOT_DATE=$$(if [ -f $(U_BOOT_BIN) ]; then stat -c%Y $(U_BOOT_BIN); else echo 0; fi); \
    KERNEL_DATE=$$(if [ -f $(KERNEL_BIN) ]; then stat -c%Y $(KERNEL_BIN); else echo 0; fi); \
    ROOTFS_DATE=$$(if [ -f $(ROOTFS_BIN) ]; then stat -c%Y $(ROOTFS_BIN); else echo 0; fi); \
    LATEST_DATE=$$(printf '%d\n' $$U_BOOT_DATE $$KERNEL_DATE $$ROOTFS_DATE | sort -gr | head -1); \
    if [ $$LATEST_DATE -eq 0 ]; then echo "missing"; else date -u +%Y%m%d%H%M -d @$$LATEST_DATE; fi).bin

FIRMWARE_BIN_FULL = $(OUTPUT_DIR)/images/$(FIRMWARE_NAME_FULL)

FIRMWARE_NAME_NOBOOT = thingino-$(BOARD)-$(shell \
    KERNEL_DATE=$$(if [ -f $(KERNEL_BIN) ]; then stat -c%Y $(KERNEL_BIN); else echo 0; fi); \
    ROOTFS_DATE=$$(if [ -f $(ROOTFS_BIN) ]; then stat -c%Y $(ROOTFS_BIN); else echo 0; fi); \
    LATEST_DATE=$$(printf '%d\n' $$KERNEL_DATE $$ROOTFS_DATE | sort -gr | head -1); \
    if [ $$LATEST_DATE -eq 0 ]; then echo "missing"; else date -u +%Y%m%d%H%M -d @$$LATEST_DATE; fi)-update.bin

FIRMWARE_BIN_NOBOOT = $(OUTPUT_DIR)/images/$(FIRMWARE_NAME_NOBOOT)

# 0x0008000б 32K, 32_768
define ALIGN_BLOCK
32768
endef

# 0x0800000, 8M, 8_388_608
define SIZE_8M
8388608
endef

# 0x1000000, 16M, 16_777_216
define SIZE_16M
16777216
endef 

# from the very beginning
define U_BOOT_OFFSET
0
endef

# 0x40000, 256K, 262_144
define U_BOOT_ENV_OFFSET
262144
endef

# 0x10000, 64K, 65_536
define U_BOOT_ENV_SIZE
65536
endef

# U_BOOT_ENV_SIZE + U_BOOT_ENV_SIZE
# 0x40000 + 0x10000 = 0x50000 = 327_680
define KERNEL_OFFSET     
327680
endef

# SIZE_8M - KERNEL_OFFSET
# 0x0800000 - 0x0050000 = 0x7B0000 = 8_060_928
define SIZE_8M_NOBOOT
8060928
endef

# SIZE_16M - KERNEL_OFFSET
# 0x1000000 - 0x0050000 = 0xFB0000 = 16_449_536 
define SIZE_16M_NOBOOT
16449536
endef

U_BOOT_SIZE = $(shell stat -c%s $(U_BOOT_BIN))
U_BOOT_SIZE_ALIGNED = $(shell echo $$((($(U_BOOT_SIZE) / $(ALIGN_BLOCK) + 1) * $(ALIGN_BLOCK))))

KERNEL_SIZE = $(shell stat -c%s $(KERNEL_BIN))
KERNEL_SIZE_ALIGNED = $(shell echo $$((($(KERNEL_SIZE) / $(ALIGN_BLOCK) + 1) * $(ALIGN_BLOCK))))

ROOTFS_SIZE = $(shell stat -c%s $(ROOTFS_BIN))
ROOTFS_SIZE_ALIGNED = $(shell echo $$((($(ROOTFS_SIZE) / $(ALIGN_BLOCK) + 1) * $(ALIGN_BLOCK))))
ROOTFS_OFFSET = $(shell echo $$(($(KERNEL_OFFSET) + $(KERNEL_SIZE_ALIGNED) )))

FIRMWARE_BIN_FULL_SIZE = $(shell stat -c%s $(FIRMWARE_BIN_FULL))
FIRMWARE_BIN_NOBOOT_SIZE = $(shell stat -c%s $(FIRMWARE_BIN_NOBOOT))

.PHONY: all toolchain sdk bootstrap clean defconfig distclean help info pack pack_full pack_update pad_full pad_update update_buildroot upload_tftp upload_sdcard upgrade_ota br-%

all: update_buildroot defconfig
ifndef BOARD
	$(MAKE) BOARD=$(BOARD) $@
endif
	@if command -v figlet >/dev/null; then figlet -f pagga $(BOARD); fi;
	$(BR2_MAKE) all
	@if command -v figlet >/dev/null; then figlet -f pagga "FINE"; fi;	

# delete all build/{package} and per-package/{package} files
br-%-dirclean: defconfig
	rm -rf $(OUTPUT_DIR)/per-package/$(subst -dirclean,,$(subst br-,,$@)) \
			$(OUTPUT_DIR)/build/$(subst -dirclean,,$(subst br-,,$@))* \
			$(OUTPUT_DIR)/target

br-savedefconfig:
	$(BR2_MAKE) $(subst br-,,$@)

br-%: defconfig
	$(BR2_MAKE) $(subst br-,,$@)

# install prerequisites
bootstrap:
ifneq ($(shell id -u), 0)
	$(error requested operation requires superuser privilege)
else
	@DEBIAN_FRONTEND=noninteractive apt-get update
	@DEBIAN_FRONTEND=noninteractive apt-get -y install build-essential bc bison cpio curl file flex git libncurses-dev make rsync unzip wget whiptail
endif

clean: defconfig
	@rm -rf $(OUTPUT_DIR)/target $(OUTPUT_DIR)/.config

defconfig: $(BUILDROOT_DIR)
	@rm -rvf $(OUTPUT_DIR)/.config
	$(BR2_MAKE) BR2_DEFCONFIG=$(BOARD_CONFIG) defconfig

delete_bin_full:
	@if [ -f $(FIRMWARE_BIN_FULL) ]; then rm $(FIRMWARE_BIN_FULL); fi

delete_bin_update:
	@if [ -f $(FIRMWARE_BIN_NOBOOT) ]; then rm $(FIRMWARE_BIN_NOBOOT); fi

distclean:
	@if [ -d "$(OUTPUT_DIR)" ]; then rm -rf $(OUTPUT_DIR); fi

menuconfig:
	$(BR2_MAKE) BR2_DEFCONFIG=$(BOARD_CONFIG) menuconfig
	$(BR2_MAKE) BR2_DEFCONFIG=$(BOARD_CONFIG) savedefconfig

pack: pack_full

pack_full: defconfig $(FIRMWARE_BIN_FULL)
	if [ $(FIRMWARE_BIN_FULL_SIZE) -gt $(SIZE_8M) ]; \
	then \
	dd if=/dev/zero bs=$(SIZE_16M) skip=0 count=1 status=none | tr '\000' '\377' > $(OUTPUT_DIR)/images/padded; \
	dd if=$(FIRMWARE_BIN_FULL) bs=$(FIRMWARE_BIN_FULL_SIZE) seek=0 count=1 of=$(OUTPUT_DIR)/images/padded conv=notrunc status=none; \
	mv $(OUTPUT_DIR)/images/padded $(FIRMWARE_BIN_FULL); \
	fi

pack_update: defconfig $(FIRMWARE_BIN_NOBOOT)
	if [ $(FIRMWARE_BIN_NOBOOT_SIZE) -gt $(SIZE_8M_NOBOOT) ]; \
	then \
	dd if=/dev/zero bs=$(SIZE_16M_NOBOOT) skip=0 count=1 status=none | tr '\000' '\377' > $(OUTPUT_DIR)/images/padded; \
	dd if=$(FIRMWARE_BIN_NOBOOT) bs=$(FIRMWARE_BIN_NOBOOT_SIZE) seek=0 count=1 of=$(OUTPUT_DIR)/images/padded conv=notrunc status=none; \
	mv $(OUTPUT_DIR)/images/padded $(FIRMWARE_BIN_NOBOOT); \
	fi

pad_full: $(FIRMWARE_BIN_FULL)
	dd if=/dev/zero bs=$(SIZE_16M) skip=0 count=1 status=none | tr '\000' '\377' > $(OUTPUT_DIR)/images/padded; \
	dd if=$(FIRMWARE_BIN_FULL) bs=$(FIRMWARE_BIN_FULL_SIZE) seek=0 count=1 of=$(OUTPUT_DIR)/images/padded conv=notrunc status=none; \
	mv $(OUTPUT_DIR)/images/padded $(FIRMWARE_BIN_FULL);

pad_update: $(FIRMWARE_BIN_NOBOOT)
	echo "--- $@"
	dd if=/dev/zero bs=$(SIZE_16M_NOBOOT) skip=0 count=1 status=none | tr '\000' '\377' > $(OUTPUT_DIR)/images/padded; \
	dd if=$(FIRMWARE_BIN_NOBOOT) bs=$(FIRMWARE_BIN_NOBOOT_SIZE) seek=0 count=1 of=$(OUTPUT_DIR)/images/padded conv=notrunc status=none; \
	mv $(OUTPUT_DIR)/images/padded $(FIRMWARE_BIN_NOBOOT);

rebuild-%:
	$(BR2_MAKE) $(subst rebuild-,,$@)-dirclean
	$(BR2_MAKE) $(subst rebuild-,,$@)

sdk: update_buildroot defconfig
ifeq ($(GCC),12)
	sed -i 's/^BR2_TOOLCHAIN_EXTERNAL_GCC_13=y/# BR2_TOOLCHAIN_EXTERNAL_GCC_13 is not set/' $(OUTPUT_DIR)/.config; \
	sed -i 's/^# BR2_TOOLCHAIN_EXTERNAL_GCC_12 is not set/BR2_TOOLCHAIN_EXTERNAL_GCC_12=y/' $(OUTPUT_DIR)/.config; \
	sed -i 's/^BR2_TOOLCHAIN_GCC_AT_LEAST_13=y/# BR2_TOOLCHAIN_GCC_AT_LEAST_13 is not set/' $(OUTPUT_DIR)/.config; \
	sed -i 's/^BR2_TOOLCHAIN_GCC_AT_LEAST="13"/BR2_TOOLCHAIN_GCC_AT_LEAST="12"/' $(OUTPUT_DIR)/.config;
endif
	$(BR2_MAKE) sdk

update_buildroot: $(SRC_DIR)
	if [ ! -d "$(SRC_DIR)" ]; then mkdir -p "$(SRC_DIR)"; fi
	if [ ! -d "$(BUILDROOT_DIR)" ]; then git clone --depth 1 $(BUILDROOT_REPO) $(BUILDROOT_DIR); fi
	cd $(BUILDROOT_DIR) && git pull && echo "Buildroot updated"

update_ota: pack_update
	scp -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -O $(FIRMWARE_BIN_NOBOOT) root@$(CAMERA_IP_ADDRESS):/tmp/fwupdate.bin
	ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no root@$(CAMERA_IP_ADDRESS) "flashcp -v /tmp/fwupdate.bin /dev/mtd5 && reboot"

# upgrade firmware using /tmp/ directory of the camera
upgrade_ota: pack
	scp -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -O $(FIRMWARE_BIN_FULL) root@$(CAMERA_IP_ADDRESS):/tmp/fwupgrade.bin
	ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no root@$(CAMERA_IP_ADDRESS) "flashcp -v /tmp/fwupgrade.bin /dev/mtd6 && reboot"

# upload firmware to tftp server
upload_tftp: $(FIRMWARE_BIN_FULL)
	busybox tftp -l $(FIRMWARE_BIN_FULL) -r $(FIRMWARE_NAME_FULL) -p $(TFTP_IP_ADDRESS)

# upload firmware to an sd card
upload_sdcard: $(FIRMWARE_BIN_FULL)
	cp -v $(FIRMWARE_BIN_FULL) $$(mount | grep $(SDCARD_DEVICE)1 | awk '{print $$3}')/autoupdate-full.bin
	sync
	umount $(SDCARD_DEVICE)1

# create output directory
$(OUTPUT_DIR):
	mkdir -p $(OUTPUT_DIR)

# create source directory
$(SRC_DIR):
	mkdir -p $(SRC_DIR)

# download Buildroot bundle
$(BUILDROOT_BUNDLE):
	$(WGET) -O $@ https://github.com/buildroot/buildroot/archive/refs/tags/$(BUILDROOT_VERSION).tar.gz
	#https://github.com/buildroot/buildroot/archive/refs/heads/master.zip

# install Buildroot sources from bundle
$(BUILDROOT_DIR)/.extracted: $(BUILDROOT_BUNDLE)
	ls -l $(dirname $@)
	mkdir -p $(SRC_DIR)
	tar -C $(SRC_DIR) -xf $(BUILDROOT_BUNDLE)
	touch $@

# download bootloader
$(U_BOOT_BIN):
	$(info U_BOOT_BIN:          $@)
	$(WGET) -O $@ $(U_BOOT_GITHUB_URL)/u-boot-$(SOC_MODEL_LESS_Z).bin

# rebuild Linux kernel
$(KERNEL_BIN):
	$(info KERNEL_BIN:          $@)
	$(info KERNEL_SIZE:         $(KERNEL_SIZE))
	$(info KERNEL_SIZE_ALIGNED: $(KERNEL_SIZE_ALIGNED))
	$(BR2_MAKE) linux-rebuild
#	mv -vf $(OUTPUT_DIR)/images/uImage $@

# rebuild rootfs
$(ROOTFS_BIN):
	$(info ROOTFS_BIN:          $@)
	$(info ROOTFS_SIZE:         $(ROOTFS_SIZE))
	$(info ROOTFS_SIZE_ALIGNED: $(ROOTFS_SIZE_ALIGNED))
	$(BR2_MAKE) all
#	mv -vf $(OUTPUT_DIR)/images/rootfs.squashfs $@

# create .tar file of rootfs
$(ROOTFS_TAR):
	$(info ROOTFS_TAR:          $@)
	$(BR2_MAKE) all
#	mv -vf $(OUTPUT_DIR)/images/rootfs.tar $@

$(FIRMWARE_BIN_FULL): $(U_BOOT_BIN) $(KERNEL_BIN) $(ROOTFS_BIN)
	dd if=/dev/zero bs=$(SIZE_8M) skip=0 count=1 status=none | tr '\000' '\377' > $@
	dd if=$(U_BOOT_BIN) bs=$(U_BOOT_SIZE) seek=$(U_BOOT_OFFSET) count=1 of=$@ conv=notrunc status=none
	dd if=$(KERNEL_BIN) bs=$(KERNEL_SIZE) seek=$(KERNEL_OFFSET)B count=1 of=$@ conv=notrunc status=none
	dd if=$(ROOTFS_BIN) bs=$(ROOTFS_SIZE) seek=$(ROOTFS_OFFSET)B count=1 of=$@ conv=notrunc status=none

$(FIRMWARE_BIN_NOBOOT): $(KERNEL_BIN) $(ROOTFS_BIN)
	dd if=/dev/zero bs=$(SIZE_8M_NOBOOT) skip=0 count=1 status=none | tr '\000' '\377' > $@
	dd if=$(KERNEL_BIN) bs=$(KERNEL_SIZE) seek=0 count=1 of=$@ conv=notrunc status=none
	dd if=$(ROOTFS_BIN) bs=$(ROOTFS_SIZE) seek=$(KERNEL_SIZE_ALIGNED)B count=1 of=$@ conv=notrunc status=none

info: defconfig
	$(info =========================================================================)
	$(info BOARD:              $(BOARD))
	$(info BOARD_CONFIG:       $(BOARD_CONFIG))
	$(info BR2_DL_DIR:         $(BR2_DL_DIR))
	$(info BR2_EXTERNAL:       $(BR2_EXTERNAL))
	$(info BR2_MAKE:           $(BR2_MAKE))
	$(info BR2_SENSOR_MODEL:   $(BR2_SENSOR_MODEL))
	$(info BUILDROOT_BUNDLE:   $(BUILDROOT_BUNDLE))
	$(info BUILDROOT_DIR:      $(BUILDROOT_DIR))
	$(info BUILDROOT_VERSION:  $(BUILDROOT_VERSION))
	$(info CAMERA_IP_ADDRESS:  $(CAMERA_IP_ADDRESS))
	$(info CURDIR:             $(CURDIR))
	$(info SOC_FAMILY:         $(SOC_FAMILY))
	$(info SOC_MODEL:          $(SOC_MODEL))
	$(info SOC_VENDOR:         $(SOC_VENDOR))
	$(info OUTPUT_DIR:         $(OUTPUT_DIR))
	$(info SCRIPTS_DIR:        $(SCRIPTS_DIR))
	$(info SRC_DIR:            $(SRC_DIR))
	$(info STDERR_LOG:         $(STDERR_LOG))
	$(info STDOUT_LOG:         $(STDOUT_LOG))
	$(info TFTP_IP_ADDRESS:    $(TFTP_IP_ADDRESS))
	$(info U_BOOT_BIN:         $(U_BOOT_BIN))
	$(info U_BOOT_GITHUB_URL:  $(U_BOOT_GITHUB_URL))
	$(info =========================================================================)

help:
	@echo "\n\
	Usage:\n\
	  - make help         - print this help\n\
	  - make bootstrap    - install system deps\n\
	  - make              - build all needed for a board (toolchain, kernel and rootfs images)\n\
	  - make pack_full    - create a full firmware file\n\
	  - make pack_update  - create an update firmware file (no bootloader)\n\
	  - make pad_full     - pad the full firmware file with zeroes to 16MB\n\
	  - make pad_update   - pad the update firmware file with zeroes to 16MB\n\
	  - make clean        - cleaning before reassembly\n\
	  - make distclean    - switching to the factory state\n\
	  - make prepare      - download and unpack buildroot\n\
	  - make info         - write to stdout information about selected board\n\
	  - make upgrade_ota CAMERA_IP_ADDRESS=192.168.1.10\n\
                      - upload the full firmware file to the camera over network, and flash it\n\
	  - make update_ota CAMERA_IP_ADDRESS=192.168.1.10\n\
                      - upload the update firmware file to the camera over network, and flash it\n\
	"
