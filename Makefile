# Thingino Firmware
# https://github.com/themactep/thingino-firmware

ifeq ($(__BASH_MAKE_COMPLETION__),1)
	exit
endif

ifneq ($(shell command -v gawk >/dev/null; echo $$?),0)
$(error Please run `make bootstrap` to install prerequisites.)
endif

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

# include device tree makefile
include $(BR2_EXTERNAL)/external.mk

# hardcoded variables
WGET := wget --quiet --no-verbose --retry-connrefused --continue --timeout=5

ifeq ($(shell command -v figlet),)
FIGLET := echo
else
FIGLET := $(shell command -v figlet) -t -f pagga
endif

U_BOOT_GITHUB_URL := https://github.com/gtxaspec/u-boot-ingenic/releases/download/latest
U_BOOT_ENV_LOCAL_TXT := $(BR2_EXTERNAL)/local.uenv.txt
U_BOOT_ENV_FINAL_TXT := $(OUTPUT_DIR)/env.txt
U_BOOT_BIN = $(OUTPUT_DIR)/images/u-boot-$(SOC_MODEL_LESS_Z).bin
U_BOOT_ENV_BIN := $(OUTPUT_DIR)/images/uenv.bin
KERNEL_BIN := $(OUTPUT_DIR)/images/uImage
ROOTFS_BIN := $(OUTPUT_DIR)/images/rootfs.squashfs
ROOTFS_TAR := $(OUTPUT_DIR)/images/rootfs.tar
OVERLAY_BIN := $(OUTPUT_DIR)/images/overlay.jffs2

# 0x0010000, 64K, 65_536
ALIGN_BLOCK := 65536

# create a full binary file suffixed with the time of the last modification to either uboot, kernel, or rootfs
FIRMWARE_NAME_FULL = thingino-$(CAMERA).bin
FIRMWARE_NAME_NOBOOT = thingino-$(CAMERA)-update.bin

FIRMWARE_BIN_FULL := $(OUTPUT_DIR)/images/$(FIRMWARE_NAME_FULL)
FIRMWARE_BIN_NOBOOT := $(OUTPUT_DIR)/images/$(FIRMWARE_NAME_NOBOOT)

# file sizes
U_BOOT_BIN_SIZE = $(shell stat -c%s $(U_BOOT_BIN))
U_BOOT_ENV_BIN_SIZE = $(shell stat -c%s $(U_BOOT_ENV_BIN))
KERNEL_BIN_SIZE = $(shell stat -c%s $(KERNEL_BIN))
ROOTFS_BIN_SIZE = $(shell stat -c%s $(ROOTFS_BIN))
OVERLAY_BIN_SIZE = $(shell stat -c%s $(OVERLAY_BIN))

FIRMWARE_BIN_FULL_SIZE = $(shell stat -c%s $(FIRMWARE_BIN_FULL))
FIRMWARE_BIN_NOBOOT_SIZE = $(shell stat -c%s $(FIRMWARE_BIN_NOBOOT))

U_BOOT_BIN_SIZE_ALIGNED = $(shell echo $$((($(U_BOOT_BIN_SIZE) / $(ALIGN_BLOCK) + 1) * $(ALIGN_BLOCK))))
KERNEL_BIN_SIZE_ALIGNED = $(shell echo $$((($(KERNEL_BIN_SIZE) / $(ALIGN_BLOCK) + 1) * $(ALIGN_BLOCK))))
ROOTFS_BIN_SIZE_ALIGNED = $(shell echo $$((($(ROOTFS_BIN_SIZE) / $(ALIGN_BLOCK) + 1) * $(ALIGN_BLOCK))))
OVERLAY_BIN_SIZE_ALIGNED = $(shell echo $$((($(OVERLAY_BIN_SIZE) / $(ALIGN_BLOCK) + 1) * $(ALIGN_BLOCK))))

# fixed size partitions
U_BOOT_PARTITION_SIZE := 262144
U_BOOT_ENV_PARTITION_SIZE := 65536
KERNEL_PARTITION_SIZE = $(KERNEL_BIN_SIZE_ALIGNED)
ROOTFS_PARTITION_SIZE = $(ROOTFS_BIN_SIZE_ALIGNED)

FIRMWARE_FULL_SIZE = $(FLASH_SIZE)
FIRMWARE_NOBOOT_SIZE = $(shell echo $$(($(FLASH_SIZE) - $(U_BOOT_PARTITION_SIZE) - $(U_BOOT_ENV_PARTITION_SIZE))))

# dynamic partitions
OVERLAY_SIZE = $(shell echo $$(($(FLASH_SIZE) - $(OVERLAY_OFFSET))))
OVERLAY_SIZE_NOBOOT = $(shell echo $$(($(FIRMWARE_NOBOOT_SIZE) - $(OVERLAY_OFFSET_NOBOOT))))

# partition offsets
U_BOOT_OFFSET = 0
U_BOOT_ENV_OFFSET = $(shell echo $$(($(U_BOOT_OFFSET) + $(U_BOOT_PARTITION_SIZE))))
KERNEL_OFFSET = $(shell echo $$(($(U_BOOT_ENV_OFFSET) + $(U_BOOT_ENV_PARTITION_SIZE))))
ROOTFS_OFFSET = $(shell echo $$(($(KERNEL_OFFSET) + $(KERNEL_PARTITION_SIZE))))
OVERLAY_OFFSET = $(shell echo $$(($(ROOTFS_OFFSET) + $(ROOTFS_PARTITION_SIZE))))

# special case with no uboot nor env
OVERLAY_OFFSET_NOBOOT = $(shell echo $$(($(KERNEL_PARTITION_SIZE) + $(ROOTFS_PARTITION_SIZE))))

BUILD_TIME = $(shell awk -F ':' 'NR==1{a=$$1} END{b=$$1} END {print (b-a)/60" min"}' $(OUTPUT_DIR)/build/build-time.log)

.PHONY: all bootstrap build clean cleanbuild create_overlay defconfig distclean \
 	help pack pack_full pack_update prepare_config reconfig sdk toolchain \
 	upload_tftp upload_sdcard upgrade_ota br-%

all: build pack
	$(info -------------------> all)
	@$(FIGLET) "FINE [$(BUILD_TIME)]"

# install prerequisites
bootstrap:
	$(info -------------------> bootstrap)
	$(SCRIPTS_DIR)/dep_check.sh

build: defconfig
	$(info -------------------> build)
	@$(FIGLET) $(CAMERA)
	$(BR2_MAKE) all

### Configuration

FRAGMENTS = $(shell awk '/FRAG:/ {$$1=$$1;gsub(/^.+:\s*/,"");print}' $(MODULE_CONFIG_REAL))

# Assemble config from bits and pieces
prepare_config: buildroot/Makefile
	$(info -------------------> prepare_config)
	# create output directory
	$(info * make OUTPUT_DIR $(OUTPUT_DIR))
	mkdir -p $(OUTPUT_DIR)
	# delete older config
	$(info * remove existing .config file)
	rm -rvf $(OUTPUT_DIR)/.config
	# gather fragments of a new config
	$(info * add fragments FRAGMENTS=$(FRAGMENTS) from $(MODULE_CONFIG_REAL))
	for i in $(FRAGMENTS); do \
	echo "** add configs/fragments/$$i.fragment"; \
	cat configs/fragments/$$i.fragment >>$(OUTPUT_DIR)/.config; \
	echo >>$(OUTPUT_DIR)/.config; \
	done
	# add module configuration
	cat $(MODULE_CONFIG_REAL) >>$(OUTPUT_DIR)/.config
ifneq ($(CAMERA_CONFIG_REAL),$(MODULE_CONFIG_REAL))
	# add camera configuration
	cat $(CAMERA_CONFIG_REAL) >>$(OUTPUT_DIR)/.config
endif
	# Add local.fragment to the final config
	if [ -f local.fragment ]; then cat local.fragment >>$(OUTPUT_DIR)/.config; fi
	# Add local.mk to the building directory to override settings
	if [ -f $(BR2_EXTERNAL)/local.mk ]; then cp -f $(BR2_EXTERNAL)/local.mk $(OUTPUT_DIR)/local.mk; fi

# Configure buildroot for a particular board
defconfig: prepare_config
	$(info -------------------> defconfig)
	cp $(OUTPUT_DIR)/.config $(OUTPUT_DIR)/.config_original
	$(BR2_MAKE) BR2_DEFCONFIG=$(CAMERA_CONFIG_REAL) olddefconfig
	# $(BR2_MAKE) BR2_DEFCONFIG=$(CAMERA_CONFIG_REAL) defconfig

select-device:
	$(info -------------------> select-device)

# Call configurator UI
menuconfig: $(OUTPUT_DIR)/.config
	$(info -------------------> menuconfig)
	$(BR2_MAKE) BR2_DEFCONFIG=$(CAMERA_CONFIG_REAL) menuconfig

# Permanently save changes to the defconfig
saveconfig:
	$(info -------------------> saveconfig)
	$(BR2_MAKE) BR2_DEFCONFIG=$(CAMERA_CONFIG_REAL) savedefconfig

### Files

clean:
	$(info -------------------> clean)
	rm -rf $(OUTPUT_DIR)/target

cleanbuild: distclean all
	$(info -------------------> cleanbuild)

distclean:
	$(info -------------------> distclean)
	if [ -d "$(OUTPUT_DIR)" ]; then rm -rf $(OUTPUT_DIR); fi

delete_bin_full:
	$(info -------------------> delete_bin_full)
	if [ -f $(FIRMWARE_BIN_FULL) ]; then rm $(FIRMWARE_BIN_FULL); fi

delete_bin_update:
	$(info -------------------> delete_bin_update)
	if [ -f $(FIRMWARE_BIN_NOBOOT) ]; then rm $(FIRMWARE_BIN_NOBOOT); fi

create_env_bin:
	:> $(U_BOOT_ENV_FINAL_TXT); \
	if [ -n "$(U_BOOT_ENV_TXT)" ] && [ -f "$(U_BOOT_ENV_TXT)" ]; then \
	cat $(U_BOOT_ENV_TXT) >> $(U_BOOT_ENV_FINAL_TXT); fi; \
	if [ -n "$(U_BOOT_ENV_LOCAL_TXT)" ] && [ -f "$(U_BOOT_ENV_LOCAL_TXT)" ]; then \
	grep --invert-match '^#' $(U_BOOT_ENV_LOCAL_TXT) >> $(U_BOOT_ENV_FINAL_TXT); fi; \
	cat $(U_BOOT_ENV_FINAL_TXT)

create_overlay: $(U_BOOT_BIN)
	$(info -------------------> create_overlay)
	if [ $(OVERLAY_SIZE) -lt 0 ]; then $(FIGLET) "OVERSIZE"; fi
	if [ -f $(OVERLAY_BIN) ]; then rm $(OVERLAY_BIN); fi
	$(OUTPUT_DIR)/host/sbin/mkfs.jffs2 --little-endian --pad=$(OVERLAY_SIZE) \
		--root=$(BR2_EXTERNAL)/overlay/upper/ --eraseblock=$(ALIGN_BLOCK) \
		--output=$(OVERLAY_BIN) --squash

pack: pack_full pack_update
	$(info -------------------> pack)

pack_full: $(FIRMWARE_BIN_FULL)
	$(info -------------------> pack_full)
	$(info FIRMWARE_BIN_FULL_SIZE:   $(FIRMWARE_BIN_FULL_SIZE))
	$(info FIRMWARE_FULL_SIZE:       $(FIRMWARE_FULL_SIZE))
	if [ $(FIRMWARE_BIN_FULL_SIZE) -gt $(FIRMWARE_FULL_SIZE) ]; then $(FIGLET) "OVERSIZE"; fi

pack_update: $(FIRMWARE_BIN_NOBOOT)
	$(info -------------------> pack_update)
	$(info FIRMWARE_BIN_NOBOOT_SIZE: $(FIRMWARE_BIN_NOBOOT_SIZE))
	$(info FIRMWARE_NOBOOT_SIZE:     $(FIRMWARE_NOBOOT_SIZE))
	if [ $(FIRMWARE_BIN_NOBOOT_SIZE) -gt $(FIRMWARE_NOBOOT_SIZE) ]; then $(FIGLET) "OVERSIZE"; fi

reconfig:
	$(info -------------------> reconfig)
	rm -rvf $(OUTPUT_DIR)/.config

rebuild-%: defconfig
	$(info -------------------> rebuild-%)
	$(BR2_MAKE) $(subst rebuild-,,$@)-dirclean $(subst rebuild-,,$@)

sdk: defconfig
	$(info -------------------> sdk)
ifeq ($(GCC),12)
	sed -i 's/^BR2_TOOLCHAIN_EXTERNAL_GCC_13=y/# BR2_TOOLCHAIN_EXTERNAL_GCC_13 is not set/' $(OUTPUT_DIR)/.config; \
	sed -i 's/^# BR2_TOOLCHAIN_EXTERNAL_GCC_12 is not set/BR2_TOOLCHAIN_EXTERNAL_GCC_12=y/' $(OUTPUT_DIR)/.config; \
	sed -i 's/^BR2_TOOLCHAIN_GCC_AT_LEAST_13=y/# BR2_TOOLCHAIN_GCC_AT_LEAST_13 is not set/' $(OUTPUT_DIR)/.config; \
	sed -i 's/^BR2_TOOLCHAIN_GCC_AT_LEAST="13"/BR2_TOOLCHAIN_GCC_AT_LEAST="12"/' $(OUTPUT_DIR)/.config;
endif
	$(BR2_MAKE) sdk

source: defconfig
	$(info -------------------> source)
	$(BR2_MAKE) BR2_DEFCONFIG=$(CAMERA_CONFIG_REAL) source

toolchain: defconfig
	$(info -------------------> sdk)
	$(BR2_MAKE) sdk

update_ota: pack_update
	$(info -------------------> update_ota)
	$(SCRIPTS_DIR)/fw_ota.sh $(FIRMWARE_BIN_NOBOOT) $(CAMERA_IP_ADDRESS)

# upgrade firmware using /tmp/ directory of the camera
upgrade_ota: pack
	$(info -------------------> upgrade_ota)
	$(SCRIPTS_DIR)/fw_ota.sh $(FIRMWARE_BIN_FULL) $(CAMERA_IP_ADDRESS)

# upload firmware to tftp server
upload_tftp: $(FIRMWARE_BIN_FULL)
	$(info -------------------> upload_ftp)
	busybox tftp -l $(FIRMWARE_BIN_FULL) -r $(FIRMWARE_NAME_FULL) -p $(TFTP_IP_ADDRESS)

# upload firmware to an sd card
upload_sdcard: $(FIRMWARE_BIN_FULL)
	$(info -------------------> upload_sdcard)
	cp -vf $(FIRMWARE_BIN_FULL) $$(mount | grep $(SDCARD_DEVICE)1 | awk '{print $$3}')/autoupdate-full.bin
	sync
	umount $(SDCARD_DEVICE)1


### Buildroot

# delete all build/{package} and per-package/{package} files
br-%-dirclean:
	$(info -------------------> br-%-dirclean)
	rm -rf $(OUTPUT_DIR)/per-package/$(subst -dirclean,,$(subst br-,,$@)) \
		$(OUTPUT_DIR)/build/$(subst -dirclean,,$(subst br-,,$@))* \
		$(OUTPUT_DIR)/target
	#  \ sed -i /^$(subst -dirclean,,$(subst br-,,$@))/d $(OUTPUT_DIR)/build/packages-file-list.txt

br-%:
	$(info -------------------> br-%)
	$(BR2_MAKE) $(subst br-,,$@)

buildroot/Makefile:
	$(info -------------------> buildroot/Makefile)
	git submodule init
	git submodule update --depth 1 --recursive

# create output directory
$(OUTPUT_DIR):
	$(info -------------------> $$(OUTPUT_DIR))
	mkdir -p $(OUTPUT_DIR)

# configure build
$(OUTPUT_DIR)/.config: defconfig
	$(info -------------------> $$(OUTPUT_DIR)/.config)

# create source directory
$(SRC_DIR):
	$(info -------------------> $$(SRC_DIR))
	mkdir -p $(SRC_DIR)

# download bootloader
$(U_BOOT_BIN):
	$(info -------------------> $$(U_BOOT_BIN))
	$(info U_BOOT_BIN not found!)
	$(WGET) -O $@ $(U_BOOT_GITHUB_URL)/u-boot-$(SOC_MODEL_LESS_Z).bin

$(U_BOOT_ENV_BIN): create_env_bin
	$(info -------------------> $$(U_BOOT_ENV_BIN))
	$(SCRIPTS_DIR)/mkenvimage -s $(U_BOOT_ENV_PARTITION_SIZE) -o $@ $(U_BOOT_ENV_FINAL_TXT)

# rebuild Linux kernel
$(KERNEL_BIN):
	$(info -------------------> $$(KERNEL_BIN))
	$(info KERNEL_BIN:            $@)
	$(info KERNEL_BIN_SIZE:       $(KERNEL_BIN_SIZE))
	$(info KERNEL_PARTITION_SIZE: $(KERNEL_PARTITON_SIZE))
	$(BR2_MAKE) linux-rebuild
#	mv -vf $(OUTPUT_DIR)/images/uImage $@

# rebuild rootfs
$(ROOTFS_BIN):
	$(info -------------------> $$(ROOTFS_BIN))
	$(info ROOTFS_BIN:            $@)
	$(info ROOTFS_BIN_SIZE:       $(ROOTFS_BIN_SIZE))
	$(info ROOTFS_PARTITION_SIZE: $(ROOTFS_PARTITION_SIZE))
	$(BR2_MAKE) all

# create .tar file of rootfs
$(ROOTFS_TAR):
	$(info -------------------> $$(ROOTFS_TAR))
	$(info ROOTFS_TAR:          $@)
	$(BR2_MAKE) all

$(OVERLAY_BIN): create_overlay
	$(info -------------------> $$(OVERLAY_BIN))
	$(info OVERLAY_BIN:         $@)
	$(info OVERLAY_BIN_SIZE:    $(OVERLAY_BIN_SIZE))
	$(info OVERLAY_OFFSET:      $(OVERLAY_OFFSET))

$(FIRMWARE_BIN_FULL): $(U_BOOT_BIN) $(U_BOOT_ENV_BIN) $(KERNEL_BIN) $(ROOTFS_BIN) $(OVERLAY_BIN)
	$(info -------------------> $$(FIRMWARE_BIN_FULL))
	$(info $(shell printf "%-10s | %8s | %9s | %9s |" PARTITION SIZE OFFSET END))
	$(info $(shell printf "%-10s | %8d | 0x%07X | 0x%07X |" U_BOOT $(U_BOOT_BIN_SIZE) $(U_BOOT_OFFSET) $$(($(U_BOOT_OFFSET) + $(U_BOOT_BIN_SIZE)))))
	$(info $(shell printf "%-10s | %8d | 0x%07X | 0x%07X |" U_BOOT_ENV $(U_BOOT_ENV_BIN_SIZE) $(U_BOOT_ENV_OFFSET) $$(($(U_BOOT_ENV_OFFSET) + $(U_BOOT_ENV_BIN_SIZE)))))
	$(info $(shell printf "%-10s | %8d | 0x%07X | 0x%07X |" KERNEL $(KERNEL_BIN_SIZE) $(KERNEL_OFFSET) $$(($(KERNEL_OFFSET) + $(KERNEL_BIN_SIZE)))))
	$(info $(shell printf "%-10s | %8d | 0x%07X | 0x%07X |" ROOTFS $(ROOTFS_BIN_SIZE) $(ROOTFS_OFFSET) $$(($(ROOTFS_OFFSET) + $(ROOTFS_BIN_SIZE)))))
	$(info $(shell printf "%-10s | %8d | 0x%07X | 0x%07X |" OVERLAY $(OVERLAY_BIN_SIZE) $(OVERLAY_OFFSET) $$(($(OVERLAY_OFFSET) + $(OVERLAY_BIN_SIZE)))))
	dd if=/dev/zero bs=$(SIZE_8M) skip=0 count=1 status=none | tr '\000' '\377' > $@
	if [ $$(dd --version | awk -F '[. ]' 'NR==1{print $$3}') -lt 9 ]; then \
	dd if=$(U_BOOT_BIN) bs=1 seek=$(U_BOOT_OFFSET) count=$(U_BOOT_BIN_SIZE) of=$@ conv=notrunc status=none; \
	dd if=$(KERNEL_BIN) bs=1 seek=$(KERNEL_OFFSET) count=$(KERNEL_BIN_SIZE) of=$@ conv=notrunc status=none; \
	dd if=$(ROOTFS_BIN) bs=1 seek=$(ROOTFS_OFFSET) count=$(ROOTFS_BIN_SIZE) of=$@ conv=notrunc status=none; \
	dd if=$(OVERLAY_BIN) bs=1 seek=$(OVERLAY_OFFSET) count=$(OVERLAY_BIN_SIZE) of=$@ conv=notrunc status=none; \
	else \
	dd if=$(U_BOOT_BIN) bs=$(U_BOOT_BIN_SIZE) seek=$(U_BOOT_OFFSET)B count=1 of=$@ conv=notrunc status=none; \
	dd if=$(KERNEL_BIN) bs=$(KERNEL_BIN_SIZE) seek=$(KERNEL_OFFSET)B count=1 of=$@ conv=notrunc status=none; \
	dd if=$(ROOTFS_BIN) bs=$(ROOTFS_BIN_SIZE) seek=$(ROOTFS_OFFSET)B count=1 of=$@ conv=notrunc status=none; \
	dd if=$(OVERLAY_BIN) bs=$(OVERLAY_BIN_SIZE) seek=$(OVERLAY_OFFSET)B count=1 of=$@ conv=notrunc status=none; \
	fi

$(FIRMWARE_BIN_NOBOOT): $(KERNEL_BIN) $(ROOTFS_BIN) $(OVERLAY_BIN)
	$(info -------------------> $$(FIRMWARE_BIN_NOBOOT))
	$(info $(shell printf "%-10s | %8s | %9s | %9s |" PARTITION SIZE OFFSET END))
	$(info $(shell printf "%-10s | %8d | 0x%07X | 0x%07X |" KERNEL $(KERNEL_BIN_SIZE) $(KERNEL_OFFSET) $$(($(KERNEL_OFFSET) + $(KERNEL_BIN_SIZE)))))
	$(info $(shell printf "%-10s | %8d | 0x%07X | 0x%07X |" ROOTFS $(ROOTFS_BIN_SIZE) $(ROOTFS_OFFSET) $$(($(ROOTFS_OFFSET) + $(ROOTFS_BIN_SIZE)))))
	$(info $(shell printf "%-10s | %8d | 0x%07X | 0x%07X |" OVERLAY $(OVERLAY_BIN_SIZE) $(OVERLAY_OFFSET) $$(($(OVERLAY_OFFSET) + $(OVERLAY_BIN_SIZE)))))
	dd if=/dev/zero bs=$(FIRMWARE_NOBOOT_SIZE) skip=0 count=1 status=none | tr '\000' '\377' > $@
	if [ $$(dd --version | awk -F '[. ]' 'NR==1{print $$3}') -lt 9 ]; then \
	dd if=$(KERNEL_BIN) bs=1 seek=0 count=$(KERNEL_BIN_SIZE) of=$@ conv=notrunc status=none; \
	dd if=$(ROOTFS_BIN) bs=1 seek=$(KERNEL_PARTITION_SIZE) count=$(ROOTFS_BIN_SIZE) of=$@ conv=notrunc status=none; \
	dd if=$(OVERLAY_BIN) bs=1 seek=$(OVERLAY_OFFSET_NOBOOT) count=$(OVERLAY_BIN_SIZE) of=$@ conv=notrunc status=none; \
	else \
	dd if=$(KERNEL_BIN) bs=$(KERNEL_BIN_SIZE) seek=0 count=1 of=$@ conv=notrunc status=none; \
	dd if=$(ROOTFS_BIN) bs=$(ROOTFS_BIN_SIZE) seek=$(KERNEL_PARTITION_SIZE)B count=1 of=$@ conv=notrunc status=none; \
	dd if=$(OVERLAY_BIN) bs=$(OVERLAY_BIN_SIZE) seek=$(OVERLAY_OFFSET_NOBOOT)B count=1 of=$@ conv=notrunc status=none; \
	fi
help:
	@echo "\n\
	Usage:\n\
	  make bootstrap      install system deps\n\
	  make defconfig      (re)create config file\n\
	  make                build and pack everything\n\
	  make build          build kernel and rootfs\n\
	  make cleanbuild     build everything from scratch\n\
	  make pack_full      create a full firmware image\n\
	  make pack_update    create an update firmware image (no bootloader)\n\
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
