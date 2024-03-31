# Thingino Firmware
# https://github.com/themactep/thingino-firmware

# Camera IP address
# shortened to just IP for convenience of running from command line
IP ?= 192.168.1.10
CAMERA_IP_ADDRESS = $(IP)

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
OUTPUT_DIR ?= $(HOME)/output/$(CAMERA)
STDOUT_LOG ?= $(OUTPUT_DIR)/compilation.log
STDERR_LOG ?= $(OUTPUT_DIR)/compilation-errors.log

# project directories
BR2_EXTERNAL := $(CURDIR)
SCRIPTS_DIR := $(CURDIR)/scripts

# make command for buildroot
BR2_MAKE = $(MAKE) -C $(BR2_EXTERNAL)/buildroot BR2_EXTERNAL=$(BR2_EXTERNAL) O=$(OUTPUT_DIR)

# handle the board
include $(BR2_EXTERNAL)/board.mk

# read camera config file
include $(CAMERA_CONFIG_REAL)

# include device tree makefile
include $(BR2_EXTERNAL)/external.mk

# hardcoded variables
WGET := wget --quiet --no-verbose --retry-connrefused --continue --timeout=3

U_BOOT_GITHUB_URL := https://github.com/gtxaspec/u-boot-ingenic/releases/download/latest
U_BOOT_BIN  = $(OUTPUT_DIR)/images/u-boot-$(SOC_MODEL_LESS_Z).bin
KERNEL_BIN := $(OUTPUT_DIR)/images/uImage
ROOTFS_BIN := $(OUTPUT_DIR)/images/rootfs.squashfs
ROOTFS_TAR := $(OUTPUT_DIR)/images/rootfs.tar

# 0x0008000, 32K, 32_768
ALIGN_BLOCK       := 32768
# 0x0800000, 8M, 8_388_608
SIZE_8M           := 8388608
# 0x1000000, 16M, 16_777_216
SIZE_16M          := 16777216

# 0x0, from the very beginning
U_BOOT_OFFSET     := 0
# 0x40000, 256K, 262_144
U_BOOT_ENV_OFFSET := 262144
# 0x10000, 64K, 65_536
U_BOOT_ENV_SIZE   := 65536

# U_BOOT_ENV_SIZE + U_BOOT_ENV_SIZE, 0x40000 + 0x10000 = 0x50000 = 327_680
KERNEL_OFFSET     := 327680
# SIZE_8M  - KERNEL_OFFSET, 0x0800000 - 0x0050000 = 0x7B0000 = 8_060_928
SIZE_8M_NOBOOT    := 8060928
# SIZE_16M - KERNEL_OFFSET, 0x1000000 - 0x0050000 = 0xFB0000 = 16_449_536
SIZE_16M_NOBOOT   := 16449536

# create a full binary file suffixed with the time of the last modification to either uboot, kernel, or rootfs
FIRMWARE_NAME_FULL = thingino-$(CAMERA)-$(shell \
    U_BOOT_DATE=$$(if [ -f $(U_BOOT_BIN) ]; then stat -c%Y $(U_BOOT_BIN); else echo 0; fi); \
    KERNEL_DATE=$$(if [ -f $(KERNEL_BIN) ]; then stat -c%Y $(KERNEL_BIN); else echo 0; fi); \
    ROOTFS_DATE=$$(if [ -f $(ROOTFS_BIN) ]; then stat -c%Y $(ROOTFS_BIN); else echo 0; fi); \
    LATEST_DATE=$$(printf '%d\n' $$U_BOOT_DATE $$KERNEL_DATE $$ROOTFS_DATE | sort -gr | head -1); \
    if [ $$LATEST_DATE -eq 0 ]; then echo "missing"; else date -u +%Y%m%d%H%M -d @$$LATEST_DATE; fi).bin

FIRMWARE_BIN_FULL = $(OUTPUT_DIR)/images/$(FIRMWARE_NAME_FULL)

FIRMWARE_NAME_NOBOOT = thingino-$(CAMERA)-$(shell \
    KERNEL_DATE=$$(if [ -f $(KERNEL_BIN) ]; then stat -c%Y $(KERNEL_BIN); else echo 0; fi); \
    ROOTFS_DATE=$$(if [ -f $(ROOTFS_BIN) ]; then stat -c%Y $(ROOTFS_BIN); else echo 0; fi); \
    LATEST_DATE=$$(printf '%d\n' $$KERNEL_DATE $$ROOTFS_DATE | sort -gr | head -1); \
    if [ $$LATEST_DATE -eq 0 ]; then echo "missing"; else date -u +%Y%m%d%H%M -d @$$LATEST_DATE; fi)-update.bin

FIRMWARE_BIN_NOBOOT = $(OUTPUT_DIR)/images/$(FIRMWARE_NAME_NOBOOT)

U_BOOT_SIZE = $(shell stat -c%s $(U_BOOT_BIN))
U_BOOT_SIZE_ALIGNED = $(shell echo $$((($(U_BOOT_SIZE) / $(ALIGN_BLOCK) + 1) * $(ALIGN_BLOCK))))

KERNEL_SIZE = $(shell stat -c%s $(KERNEL_BIN))
KERNEL_SIZE_ALIGNED = $(shell echo $$((($(KERNEL_SIZE) / $(ALIGN_BLOCK) + 1) * $(ALIGN_BLOCK))))

ROOTFS_SIZE = $(shell stat -c%s $(ROOTFS_BIN))
ROOTFS_SIZE_ALIGNED = $(shell echo $$((($(ROOTFS_SIZE) / $(ALIGN_BLOCK) + 1) * $(ALIGN_BLOCK))))
ROOTFS_OFFSET = $(shell echo $$(($(KERNEL_OFFSET) + $(KERNEL_SIZE_ALIGNED) )))

FIRMWARE_BIN_FULL_SIZE = $(shell stat -c%s $(FIRMWARE_BIN_FULL))
FIRMWARE_BIN_NOBOOT_SIZE = $(shell stat -c%s $(FIRMWARE_BIN_NOBOOT))

.PHONY: all toolchain sdk bootstrap clean defconfig distclean help \
	pack pack_full pack_update pad pad_full pad_update reconfig \
	upload_tftp upload_sdcard upgrade_ota br-%

all: $(OUTPUT_DIR)/.config
	$(info --------------> all)
#ifndef CAMERA
#	$(MAKE) CAMERA=$(CAMERA) $@
#endif
	@if command -v figlet >/dev/null; then figlet -t -f pagga $(CAMERA); fi;
	# Generate .config file
	if ! test -f $(OUTPUT_DIR)/.config; then $(BR2_MAKE) BR2_DEFCONFIG=$(CAMERA_CONFIG_REAL) defconfig; fi
#	# Add local.mk to the building directory to override settings
#	if test -f $(BR2_EXTERNAL)/local.mk; then cp -f $(BR2_EXTERNAL)/local.mk $(OUTPUT_DIR)/local.mk; fi
	$(BR2_MAKE) all
	@if command -v figlet >/dev/null; then figlet -t -f pagga "FINE"; fi;

# install prerequisites
bootstrap:
	$(info --------------> bootstrap)
ifneq ($(shell id -u), 0)
	$(error requested operation requires superuser privilege)
else
	@DEBIAN_FRONTEND=noninteractive apt-get update
	@DEBIAN_FRONTEND=noninteractive apt-get -y install \
		build-essential bc bison cpio curl file flex git \
		libncurses-dev make rsync unzip wget whiptail
endif

### Configuration

FRAGMENTS = $(shell awk '/FRAG:/ {$$1=$$1;gsub(/^.+:\s*/,"");print}' $(CAMERA_CONFIG_REAL))

# Configure buildroot for a particular board
defconfig:
	$(info --------------> defconfig)
	$(info * make OUTPUT_DIR $(OUTPUT_DIR))
	mkdir -p $(OUTPUT_DIR)
	$(info * remove existing .config file)
	rm -rvf $(OUTPUT_DIR)/.config
	$(info * add fragments FRAGMENTS=$(FRAGMENTS))
	for i in $(FRAGMENTS); do \
		echo "** add configs/fragments/$$i.fragment"; \
		cat configs/fragments/$$i.fragment >>$(OUTPUT_DIR)/.config; \
		echo >>$(OUTPUT_DIR)/.config; \
	done
	cat $(CAMERA_CONFIG_REAL) >>$(OUTPUT_DIR)/.config
	$(BR2_MAKE) BR2_DEFCONFIG=$(CAMERA_CONFIG_REAL) olddefconfig
	# $(BR2_MAKE) BR2_DEFCONFIG=$(CAMERA_CONFIG_REAL) defconfig
	# @if test -f $(BR2_EXTERNAL)/local.mk; then cp -f $(BR2_EXTERNAL)/local.mk $(OUTPUT_DIR)/local.mk; fi

defconfig_classic:
	$(info --------------> defconfig_classic)
	$(BR2_MAKE) BR2_DEFCONFIG=$(CAMERA_CONFIG_REAL) defconfig
	# Add local.mk to the building directory to override settings
	if test -f $(BR2_EXTERNAL)/local.mk; then cp -f $(BR2_EXTERNAL)/local.mk $(OUTPUT_DIR)/local.mk; fi

# Call configurator UI
menuconfig: $(OUTPUT_DIR)/.config
	$(info --------------> menuconfig)
	$(BR2_MAKE) BR2_DEFCONFIG=$(CAMERA_CONFIG_REAL) menuconfig

# Permanently save changes to the defconfig
saveconfig:
	$(info --------------> saveconfig)
	$(BR2_MAKE) BR2_DEFCONFIG=$(CAMERA_CONFIG_REAL) savedefconfig

### Files

clean:
	$(info --------------> clean)
	rm -rf $(OUTPUT_DIR)/target

distclean:
	$(info --------------> distclean)
	if [ -d "$(OUTPUT_DIR)" ]; then rm -rf $(OUTPUT_DIR); fi

delete_bin_full:
	if [ -f $(FIRMWARE_BIN_FULL) ]; then rm $(FIRMWARE_BIN_FULL); fi

delete_bin_update:
	if [ -f $(FIRMWARE_BIN_NOBOOT) ]; then rm $(FIRMWARE_BIN_NOBOOT); fi

pack: pack_full
	$(info --------------> pack)

pack_full: $(FIRMWARE_BIN_FULL)
	$(info --------------> pack_full)
	if [ $(FIRMWARE_BIN_FULL_SIZE) -gt $(SIZE_8M) ]; \
	then \
	dd if=/dev/zero bs=$(SIZE_16M) skip=0 count=1 status=none | tr '\000' '\377' > $(OUTPUT_DIR)/images/padded; \
	dd if=$(FIRMWARE_BIN_FULL) bs=$(FIRMWARE_BIN_FULL_SIZE) seek=0 count=1 of=$(OUTPUT_DIR)/images/padded conv=notrunc status=none; \
	mv $(OUTPUT_DIR)/images/padded $(FIRMWARE_BIN_FULL); \
	fi

pack_update: $(FIRMWARE_BIN_NOBOOT)
	$(info --------------> pack_update)
	if [ $(FIRMWARE_BIN_NOBOOT_SIZE) -gt $(SIZE_8M_NOBOOT) ]; \
	then \
	dd if=/dev/zero bs=$(SIZE_16M_NOBOOT) skip=0 count=1 status=none | tr '\000' '\377' > $(OUTPUT_DIR)/images/padded; \
	dd if=$(FIRMWARE_BIN_NOBOOT) bs=$(FIRMWARE_BIN_NOBOOT_SIZE) seek=0 count=1 of=$(OUTPUT_DIR)/images/padded conv=notrunc status=none; \
	mv $(OUTPUT_DIR)/images/padded $(FIRMWARE_BIN_NOBOOT); \
	fi

pad: pad_full
	$(info --------------> pad)

pad_full: $(FIRMWARE_BIN_FULL)
	$(info --------------> pad_full)
	dd if=/dev/zero bs=$(SIZE_16M) skip=0 count=1 status=none | tr '\000' '\377' > $(OUTPUT_DIR)/images/padded; \
	dd if=$(FIRMWARE_BIN_FULL) bs=$(FIRMWARE_BIN_FULL_SIZE) seek=0 count=1 of=$(OUTPUT_DIR)/images/padded conv=notrunc status=none; \
	mv $(OUTPUT_DIR)/images/padded $(FIRMWARE_BIN_FULL);

pad_update: $(FIRMWARE_BIN_NOBOOT)
	$(info --------------> pad_update)
	dd if=/dev/zero bs=$(SIZE_16M_NOBOOT) skip=0 count=1 status=none | tr '\000' '\377' > $(OUTPUT_DIR)/images/padded; \
	dd if=$(FIRMWARE_BIN_NOBOOT) bs=$(FIRMWARE_BIN_NOBOOT_SIZE) seek=0 count=1 of=$(OUTPUT_DIR)/images/padded conv=notrunc status=none; \
	mv $(OUTPUT_DIR)/images/padded $(FIRMWARE_BIN_NOBOOT);

reconfig:
	rm -rvf $(OUTPUT_DIR)/.config

rebuild-%:
	$(BR2_MAKE) $(subst rebuild-,,$@)-dirclean
	$(BR2_MAKE) $(subst rebuild-,,$@)

sdk: defconfig
ifeq ($(GCC),12)
	sed -i 's/^BR2_TOOLCHAIN_EXTERNAL_GCC_13=y/# BR2_TOOLCHAIN_EXTERNAL_GCC_13 is not set/' $(OUTPUT_DIR)/.config; \
	sed -i 's/^# BR2_TOOLCHAIN_EXTERNAL_GCC_12 is not set/BR2_TOOLCHAIN_EXTERNAL_GCC_12=y/' $(OUTPUT_DIR)/.config; \
	sed -i 's/^BR2_TOOLCHAIN_GCC_AT_LEAST_13=y/# BR2_TOOLCHAIN_GCC_AT_LEAST_13 is not set/' $(OUTPUT_DIR)/.config; \
	sed -i 's/^BR2_TOOLCHAIN_GCC_AT_LEAST="13"/BR2_TOOLCHAIN_GCC_AT_LEAST="12"/' $(OUTPUT_DIR)/.config;
endif
	$(BR2_MAKE) sdk

source: defconfig
	$(BR2_MAKE) BR2_DEFCONFIG=$(CAMERA_CONFIG_REAL) source

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


### Buildroot

# delete all build/{package} and per-package/{package} files
br-%-dirclean:
	rm -rf $(OUTPUT_DIR)/per-package/$(subst -dirclean,,$(subst br-,,$@)) \
	       $(OUTPUT_DIR)/build/$(subst -dirclean,,$(subst br-,,$@))* \
	       $(OUTPUT_DIR)/target
#  \ sed -i /^$(subst -dirclean,,$(subst br-,,$@))/d $(OUTPUT_DIR)/build/packages-file-list.txt

br-%:
	$(BR2_MAKE) $(subst br-,,$@)


# create output directory
$(OUTPUT_DIR):
	mkdir -p $(OUTPUT_DIR)

# configure build
$(OUTPUT_DIR)/.config: defconfig

# create source directory
$(SRC_DIR):
	mkdir -p $(SRC_DIR)

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
	$(info --------------> ROOTFS_TAR=$(ROOTFS_TAR))
	$(info ROOTFS_TAR:          $@)
	$(BR2_MAKE) all
#	mv -vf $(OUTPUT_DIR)/images/rootfs.tar $@

$(FIRMWARE_BIN_FULL): $(U_BOOT_BIN) $(KERNEL_BIN) $(ROOTFS_BIN)
	$(info --------------> FIRMWARE_BIN_FULL=$(FIRMWARE_BIN_FULL))
	dd if=/dev/zero bs=$(SIZE_8M) skip=0 count=1 status=none | tr '\000' '\377' > $@
	dd if=$(U_BOOT_BIN) bs=$(U_BOOT_SIZE) seek=$(U_BOOT_OFFSET) count=1 of=$@ conv=notrunc status=none
	dd if=$(KERNEL_BIN) bs=$(KERNEL_SIZE) seek=$(KERNEL_OFFSET)B count=1 of=$@ conv=notrunc status=none
	dd if=$(ROOTFS_BIN) bs=$(ROOTFS_SIZE) seek=$(ROOTFS_OFFSET)B count=1 of=$@ conv=notrunc status=none

$(FIRMWARE_BIN_NOBOOT): $(KERNEL_BIN) $(ROOTFS_BIN)
	$(info --------------> FIRMWARE_BIN_NOBOOT=$(FIRMWARE_BIN_NOBOOT))
	dd if=/dev/zero bs=$(SIZE_8M_NOBOOT) skip=0 count=1 status=none | tr '\000' '\377' > $@
	dd if=$(KERNEL_BIN) bs=$(KERNEL_SIZE) seek=0 count=1 of=$@ conv=notrunc status=none
	dd if=$(ROOTFS_BIN) bs=$(ROOTFS_SIZE) seek=$(KERNEL_SIZE_ALIGNED)B count=1 of=$@ conv=notrunc status=none

help:
	@echo "\n\
	Usage:\n\
	  make bootstrap      install system deps\n\
	  make                build everything needed for the board\n\
	                        (toolchain, kernel, and rootfs)\n\
	  make pack_full      create a full firmware image\n\
	  make pack_update    create an update firmware image (no bootloader)\n\
	  make pad_full       pad the full firmware image to 16MB\n\
	  make pad_update     pad the update firmware image to 16MB\n\
	  make clean          clean before reassembly\n\
	  make distclean      start building from scratch\n\
	  make rebuild-<pkg>  perform a clean package rebuild for <pkg>\n\
	  make help           print this help\n\
	  \n\
	  make upgrade_ota IP=192.168.1.10\n\
	                      upload the full firmware file to the camera\n\
	                        over network, and flash it\n\n\
	  make update_ota IP=192.168.1.10\n\
	                      upload the update firmware file to the camera\n\
	                        over network, and flash it\n\n\
	"
