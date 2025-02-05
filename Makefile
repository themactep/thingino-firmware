# Thingino Firmware
# https://github.com/themactep/thingino-firmware

ifeq ($(__BASH_MAKE_COMPLETION__),1)
	exit
endif

ifneq ($(shell command -v gawk >/dev/null; echo $$?),0)
$(error Please install gawk)
endif

ifneq ($(shell command -v mkimage >/dev/null; echo $$?),0)
$(error Please install mkimage from u-boot-tools)
endif

ifneq ($(findstring $(empty) $(empty),$(CURDIR)),)
$(error Current directory path "$(CURDIR)" cannot contain spaces)
endif

# Camera IP address
# shortened to just IP for convenience of running from command line
IP ?= 192.168.1.10
CAMERA_IP_ADDRESS := $(IP)

# Device of SD card
SDCARD_DEVICE ?= /dev/sdf

# TFTP server IP address to upload compiled images to
TFTP_IP_ADDRESS ?= 192.168.1.254

# project directories
BR2_EXTERNAL := $(CURDIR)
SCRIPTS_DIR := $(BR2_EXTERNAL)/scripts

# Buildroot downloads directory
# can be reused from environment, just export the value:
# export BR2_DL_DIR = /path/to/your/local/storage
BR2_DL_DIR ?= $(HOME)/dl

#ifeq ($(BOARD),)
#$(error No camera config provided)
#else
#CAMERA:=$(BOARD)
#$(info Building for CAMERA: $(CAMERA))
#endif

# working directory
GIT_BRANCH := $(shell git branch --show-current)
ifeq ($(GIT_BRANCH),master)
OUTPUT_DIR ?= $(HOME)/output/$(CAMERA)
else
OUTPUT_DIR ?= $(HOME)/output-$(GIT_BRANCH)/$(CAMERA)
endif
$(info OUTPUT_DIR: $(OUTPUT_DIR))
export OUTPUT_DIR

CONFIG_PARTITION_DIR = $(OUTPUT_DIR)/config
export CONFIG_PARTITION_DIR

STDOUT_LOG ?= $(OUTPUT_DIR)/compilation.log
STDERR_LOG ?= $(OUTPUT_DIR)/compilation-errors.log

# handle the board
include $(BR2_EXTERNAL)/board.mk

# include thingino makefile
include $(BR2_EXTERNAL)/thingino.mk

# hardcoded variables
WGET := wget --quiet --no-verbose --retry-connrefused --continue --timeout=5

ifeq ($(shell command -v figlet),)
FIGLET := echo
else
FIGLET := $(shell command -v figlet) -t -f pagga
endif

SIZE_32M := 33554432
SIZE_16M := 16777216
SIZE_8M := 8388608
SIZE_256K := 262144
SIZE_192K := 196608
SIZE_128K := 131072
SIZE_64K := 65536
SIZE_32K := 32768
SIZE_16K := 16384
SIZE_8K := 8192
SIZE_4K := 4096

ALIGN_BLOCK := $(SIZE_64K)

U_BOOT_GITHUB_URL := https://github.com/gtxaspec/u-boot-ingenic/releases/download/latest

ifeq ($(BR2_PACKAGE_THINGINO_UBOOT_FORMAT_CUSTOM_NAME),)
U_BOOT_BIN = $(OUTPUT_DIR)/images/u-boot-lzo-with-spl.bin
else
U_BOOT_BIN = $(OUTPUT_DIR)/images/$(patsubst "%",%,$(BR2_PACKAGE_THINGINO_UBOOT_FORMAT_CUSTOM_NAME))
endif

UB_ENV_FINAL_TXT = $(OUTPUT_DIR)/uenv.txt
export UB_ENV_FINAL_TXT

UB_ENV_BIN = $(OUTPUT_DIR)/images/u-boot-env.bin
CONFIG_BIN := $(OUTPUT_DIR)/images/config.ext2
KERNEL_BIN := $(OUTPUT_DIR)/images/uImage
ROOTFS_BIN := $(OUTPUT_DIR)/images/rootfs.squashfs
ROOTFS_TAR := $(OUTPUT_DIR)/images/rootfs.tar
OVERLY_BIN := $(OUTPUT_DIR)/images/overlay.jffs2

# create a full binary file suffixed with the time of the last modification to either uboot, kernel, or rootfs
FIRMWARE_NAME_FULL = thingino-$(CAMERA).bin
FIRMWARE_NAME_NOBOOT = thingino-$(CAMERA)-update.bin

FIRMWARE_BIN_FULL := $(OUTPUT_DIR)/images/$(FIRMWARE_NAME_FULL)
FIRMWARE_BIN_NOBOOT := $(OUTPUT_DIR)/images/$(FIRMWARE_NAME_NOBOOT)

# file sizes
U_BOOT_BIN_SIZE = $(shell stat -c%s $(U_BOOT_BIN))
UB_ENV_BIN_SIZE = $(shell stat -c%s $(UB_ENV_BIN))
CONFIG_BIN_SIZE = $(shell stat -c%s $(CONFIG_BIN))
KERNEL_BIN_SIZE = $(shell stat -c%s $(KERNEL_BIN))
ROOTFS_BIN_SIZE = $(shell stat -c%s $(ROOTFS_BIN))
OVERLY_BIN_SIZE = $(shell stat -c%s $(OVERLY_BIN))

FIRMWARE_BIN_FULL_SIZE = $(shell stat -c%s $(FIRMWARE_BIN_FULL))
FIRMWARE_BIN_NOBOOT_SIZE = $(shell stat -c%s $(FIRMWARE_BIN_NOBOOT))

U_BOOT_BIN_SIZE_ALIGNED = $(shell echo $$((($(U_BOOT_BIN_SIZE) + $(ALIGN_BLOCK) - 1) / $(ALIGN_BLOCK) * $(ALIGN_BLOCK))))
UB_ENV_BIN_SIZE_ALIGNED = $(shell echo $$((($(UB_ENV_BIN_SIZE) + $(ALIGN_BLOCK) - 1) / $(ALIGN_BLOCK) * $(ALIGN_BLOCK))))
CONFIG_BIN_SIZE_ALIGNED = $(shell echo $$((($(CONFIG_BIN_SIZE) + $(ALIGN_BLOCK) - 1) / $(ALIGN_BLOCK) * $(ALIGN_BLOCK))))
KERNEL_BIN_SIZE_ALIGNED = $(shell echo $$((($(KERNEL_BIN_SIZE) + $(ALIGN_BLOCK) - 1) / $(ALIGN_BLOCK) * $(ALIGN_BLOCK))))
ROOTFS_BIN_SIZE_ALIGNED = $(shell echo $$((($(ROOTFS_BIN_SIZE) + $(ALIGN_BLOCK) - 1) / $(ALIGN_BLOCK) * $(ALIGN_BLOCK))))
OVERLY_BIN_SIZE_ALIGNED = $(shell echo $$((($(OVERLY_BIN_SIZE) + $(ALIGN_BLOCK) - 1) / $(ALIGN_BLOCK) * $(ALIGN_BLOCK))))

# fixed size partitions
U_BOOT_PARTITION_SIZE := $(SIZE_256K)
UB_ENV_PARTITION_SIZE := $(SIZE_64K)
CONFIG_PARTITION_SIZE := $(SIZE_64K)
KERNEL_PARTITION_SIZE = $(KERNEL_BIN_SIZE_ALIGNED)
ROOTFS_PARTITION_SIZE = $(ROOTFS_BIN_SIZE_ALIGNED)

FIRMWARE_FULL_SIZE = $(FLASH_SIZE)
FIRMWARE_NOBOOT_SIZE = $(shell echo $$(($(FLASH_SIZE) - $(U_BOOT_PARTITION_SIZE) - $(UB_ENV_PARTITION_SIZE) - $(CONFIG_PARTITION_SIZE))))

# dynamic partitions
OVERLY_PARTITION_SIZE = $(shell echo $$(($(FLASH_SIZE) - $(OVERLY_OFFSET))))
OVERLY_ERASEBLOCK_SIZE := $(shell echo $$(($(ALIGN_BLOCK) * 1)))
OVERLY_LLIMIT := $(shell echo $$(($(ALIGN_BLOCK) * 5)))

# partition offsets
U_BOOT_OFFSET := 0
UB_ENV_OFFSET = $(shell echo $$(($(U_BOOT_OFFSET) + $(U_BOOT_PARTITION_SIZE))))
CONFIG_OFFSET = $(shell echo $$(($(UB_ENV_OFFSET) + $(UB_ENV_PARTITION_SIZE))))
KERNEL_OFFSET = $(shell echo $$(($(CONFIG_OFFSET) + $(CONFIG_PARTITION_SIZE))))
#KERNEL_OFFSET = $(shell echo $$(($(UB_ENV_OFFSET) + $(UB_ENV_PARTITION_SIZE))))
ROOTFS_OFFSET = $(shell echo $$(($(KERNEL_OFFSET) + $(KERNEL_PARTITION_SIZE))))
OVERLY_OFFSET = $(shell echo $$(($(ROOTFS_OFFSET) + $(ROOTFS_PARTITION_SIZE))))

# special case with no uboot nor env
OVERLY_OFFSET_NOBOOT = $(shell echo $$(($(KERNEL_PARTITION_SIZE) + $(ROOTFS_PARTITION_SIZE))))

# repo data
GIT_BRANCH="$(shell git branch | grep '^*' | awk '{print $$2}')"
GIT_HASH="$(shell git show -s --format=%H | cut -c1-7)"
GIT_DATE="$(TZ=UTC0 git show --quiet --date='format-local:%Y-%m-%d %H:%M:%S UTC' --format="%cd")"
BUILD_DATE="$(shell env -u SOURCE_DATE_EPOCH TZ=UTC date '+%Y-%m-%d %H:%M:%S %z')"

RELEASE = 0

# make command for buildroot
BR2_MAKE = $(MAKE) -C $(BR2_EXTERNAL)/buildroot BR2_EXTERNAL=$(BR2_EXTERNAL) O=$(OUTPUT_DIR)

.PHONY: all bootstrap build build_fast clean cleanbuild defconfig distclean fast \
	help pack release sdk toolchain update upboot-ota upload_tftp upgrade_ota br-%

all: defconfig build pack
	$(info -------------------------------- $@)

fast: defconfig build_fast pack
	$(info -------------------------------- $@)

# rebuild from scratch
cleanbuild: distclean defconfig build_fast pack
	$(info -------------------------------- $@)

release: RELEASE=1
release: distclean defconfig build_fast pack
	$(info -------------------------------- $@)

# update repo and submodules
update:
	$(info -------------------------------- $@)
	git pull --rebase --autostash
	git submodule update

# install what's needed
bootstrap:
	$(info -------------------------------- $@)
	$(SCRIPTS_DIR)/dep_check.sh

build: $(UB_ENV_FINAL_TXT)
	$(info -------------------------------- $@)
	$(BR2_MAKE) all

build_fast: $(UB_ENV_FINAL_TXT)
	$(info -------------------------------- $@)
	$(BR2_MAKE) -j$(shell nproc) all

### Configuration

FRAGMENTS = $(shell awk '/FRAG:/ {$$1=$$1;gsub(/^.+:\s*/,"");print}' $(MODULE_CONFIG_REAL))

# Configure buildroot for a particular board
defconfig: buildroot/Makefile $(OUTPUT_DIR)/.config
	$(info -------------------------------- $@)
	@$(FIGLET) $(CAMERA)

select-device:
	$(info -------------------------------- $@)

# call configurator
menuconfig: $(OUTPUT_DIR)/.config
	$(info -------------------------------- $@)
	$(BR2_MAKE) BR2_DEFCONFIG=$(CAMERA_CONFIG_REAL) menuconfig

nconfig: $(OUTPUT_DIR)/.config
	$(info -------------------------------- $@)
	$(BR2_MAKE) BR2_DEFCONFIG=$(CAMERA_CONFIG_REAL) nconfig

# permanently save changes to the defconfig
saveconfig:
	$(info -------------------------------- $@)
	$(BR2_MAKE) BR2_DEFCONFIG=$(CAMERA_CONFIG_REAL) savedefconfig

### Files

# remove target/ directory
clean:
	$(info -------------------------------- $@)
	rm -rf $(OUTPUT_DIR)/target

# remove all build files
distclean:
	$(info -------------------------------- $@)
	if [ -d "$(OUTPUT_DIR)" ]; then rm -rf $(OUTPUT_DIR); fi

# assemble final images
pack: $(FIRMWARE_BIN_FULL) $(FIRMWARE_BIN_NOBOOT)
	$(info -------------------------------- $@)
	@$(FIGLET) $(CAMERA)
	$(info ALIGNMENT: $(ALIGN_BLOCK))
	$(info  )
	$(info $(shell printf "%-7s | %8s | %8s | %8s | %8s | %8s | %8s |" NAME OFFSET PT_SIZE CONTENT ALIGNED END LOSS))
	$(info $(shell printf "%-7s | %8d | %8d | %8d | %8d | %8d | %8d |" U_BOOT $(U_BOOT_OFFSET) $(U_BOOT_PARTITION_SIZE) $(U_BOOT_BIN_SIZE) $(U_BOOT_BIN_SIZE_ALIGNED) $$(($(U_BOOT_OFFSET) + $(U_BOOT_BIN_SIZE_ALIGNED))) $$(($(U_BOOT_PARTITION_SIZE) - $(U_BOOT_BIN_SIZE_ALIGNED))) ))
	$(info $(shell printf "%-7s | %8d | %8d | %8d | %8d | %8d | %8d |" UB_ENV $(UB_ENV_OFFSET) $(UB_ENV_PARTITION_SIZE) $(UB_ENV_BIN_SIZE) $(UB_ENV_BIN_SIZE_ALIGNED) $$(($(UB_ENV_OFFSET) + $(UB_ENV_BIN_SIZE_ALIGNED))) $$(($(UB_ENV_PARTITION_SIZE) - $(UB_ENV_BIN_SIZE_ALIGNED))) ))
	$(info $(shell printf "%-7s | %8d | %8d | %8d | %8d | %8d | %8d |" CONFIG $(CONFIG_OFFSET) $(CONFIG_PARTITION_SIZE) $(CONFIG_BIN_SIZE) $(CONFIG_BIN_SIZE_ALIGNED) $$(($(CONFIG_OFFSET) + $(CONFIG_BIN_SIZE_ALIGNED))) $$(($(CONFIG_PARTITION_SIZE) - $(CONFIG_BIN_SIZE_ALIGNED))) ))
	$(info $(shell printf "%-7s | %8d | %8d | %8d | %8d | %8d | %8d |" KERNEL $(KERNEL_OFFSET) $(KERNEL_PARTITION_SIZE) $(KERNEL_BIN_SIZE) $(KERNEL_PARTITION_SIZE) $$(($(KERNEL_OFFSET) + $(KERNEL_PARTITION_SIZE))) $$(($(KERNEL_PARTITION_SIZE) - $(KERNEL_PARTITION_SIZE))) ))
	$(info $(shell printf "%-7s | %8d | %8d | %8d | %8d | %8d | %8d |" ROOTFS $(ROOTFS_OFFSET) $(ROOTFS_PARTITION_SIZE) $(ROOTFS_BIN_SIZE) $(ROOTFS_PARTITION_SIZE) $$(($(ROOTFS_OFFSET) + $(ROOTFS_PARTITION_SIZE))) $$(($(ROOTFS_PARTITION_SIZE) - $(ROOTFS_PARTITION_SIZE))) ))
	$(info $(shell printf "%-7s | %8d | %8d | %8d | %8d | %8d | %8d |" OVERLAY $(OVERLY_OFFSET) $(OVERLY_PARTITION_SIZE) $(OVERLY_BIN_SIZE) $(OVERLY_BIN_SIZE_ALIGNED) $$(($(OVERLY_OFFSET) + $(OVERLY_BIN_SIZE_ALIGNED))) $$(($(OVERLY_PARTITION_SIZE) - $(OVERLY_BIN_SIZE_ALIGNED))) ))
	$(info  )
	$(info $(shell printf "%-7s | %8s | %8s | %8s | %8s | %8s | %8s |" NAME OFFSET PT_SIZE CONTENT ALIGNED END LOSS))
	$(info $(shell printf "%-7s | %08X | %08X | %08X | %08X | %08X | %08X |" U_BOOT $(U_BOOT_OFFSET) $(U_BOOT_PARTITION_SIZE) $(U_BOOT_BIN_SIZE) $(U_BOOT_BIN_SIZE_ALIGNED) $$(($(U_BOOT_OFFSET) + $(U_BOOT_BIN_SIZE_ALIGNED))) $$(($(U_BOOT_PARTITION_SIZE) - $(U_BOOT_BIN_SIZE_ALIGNED))) ))
	$(info $(shell printf "%-7s | %08X | %08X | %08X | %08X | %08X | %08X |" ENV $(UB_ENV_OFFSET) $(UB_ENV_PARTITION_SIZE) $(UB_ENV_BIN_SIZE) $(UB_ENV_BIN_SIZE_ALIGNED) $$(($(UB_ENV_OFFSET) + $(UB_ENV_BIN_SIZE_ALIGNED))) $$(($(UB_ENV_PARTITION_SIZE) - $(UB_ENV_BIN_SIZE_ALIGNED))) ))
	$(info $(shell printf "%-7s | %08X | %08X | %08X | %08X | %08X | %08X |" CONFIG $(CONFIG_OFFSET) $(CONFIG_PARTITION_SIZE) $(CONFIG_BIN_SIZE) $(CONFIG_BIN_SIZE_ALIGNED) $$(($(CONFIG_OFFSET) + $(CONFIG_BIN_SIZE_ALIGNED))) $$(($(CONFIG_PARTITION_SIZE) - $(CONFIG_BIN_SIZE_ALIGNED))) ))
	$(info $(shell printf "%-7s | %08X | %08X | %08X | %08X | %08X | %08X |" KERNEL $(KERNEL_OFFSET) $(KERNEL_PARTITION_SIZE) $(KERNEL_BIN_SIZE) $(KERNEL_PARTITION_SIZE) $$(($(KERNEL_OFFSET) + $(KERNEL_PARTITION_SIZE))) $$(($(KERNEL_PARTITION_SIZE) - $(KERNEL_PARTITION_SIZE))) ))
	$(info $(shell printf "%-7s | %08X | %08X | %08X | %08X | %08X | %08X |" ROOTFS $(ROOTFS_OFFSET) $(ROOTFS_PARTITION_SIZE) $(ROOTFS_BIN_SIZE) $(ROOTFS_PARTITION_SIZE) $$(($(ROOTFS_OFFSET) + $(ROOTFS_PARTITION_SIZE))) $$(($(ROOTFS_PARTITION_SIZE) - $(ROOTFS_PARTITION_SIZE))) ))
	$(info $(shell printf "%-7s | %08X | %08X | %08X | %08X | %08X | %08X |" OVERLAY $(OVERLY_OFFSET) $(OVERLY_PARTITION_SIZE) $(OVERLY_BIN_SIZE) $(OVERLY_BIN_SIZE_ALIGNED) $$(($(OVERLY_OFFSET) + $(OVERLY_BIN_SIZE_ALIGNED))) $$(($(OVERLY_PARTITION_SIZE) - $(OVERLY_BIN_SIZE_ALIGNED))) ))
	$(info  )

	if [ $(FIRMWARE_BIN_FULL_SIZE) -gt $(FIRMWARE_FULL_SIZE) ]; then $(FIGLET) "OVERSIZE"; fi
	rm -f $(FIRMWARE_BIN_FULL).sha256sum
	echo "$(shell echo \# $(CAMERA))" >> $(FIRMWARE_BIN_FULL).sha256sum
	echo "# ${GIT_BRANCH}+${GIT_HASH}, ${BUILD_DATE}" >> "$(FIRMWARE_BIN_FULL).sha256sum"
	sha256sum $(FIRMWARE_BIN_FULL) | awk '{print $$1 "  " filename}' filename="$(FIRMWARE_NAME_FULL)" >> $(FIRMWARE_BIN_FULL).sha256sum

	if [ $(FIRMWARE_BIN_NOBOOT_SIZE) -gt $(FIRMWARE_NOBOOT_SIZE) ]; then $(FIGLET) "OVERSIZE"; fi
	rm -f $(FIRMWARE_BIN_NOBOOT).sha256sum
	echo "$(shell echo \# $(CAMERA))" >> $(FIRMWARE_BIN_NOBOOT).sha256sum
	echo "# ${GIT_BRANCH}+${GIT_HASH}, ${BUILD_DATE}" >> "$(FIRMWARE_BIN_NOBOOT).sha256sum"
	sha256sum $(FIRMWARE_BIN_NOBOOT) | awk '{print $$1 "  " filename}' filename="$(FIRMWARE_NAME_NOBOOT)" >> $(FIRMWARE_BIN_NOBOOT).sha256sum
	@$(FIGLET) "FINE"

# rebuild a package
rebuild-%: defconfig
	$(info -------------------------------- $@)
	$(BR2_MAKE) $(subst rebuild-,,$@)-dirclean $(subst rebuild-,,$@)

# build toolchain fast
sdk: defconfig
	$(info -------------------------------- $@)
	$(BR2_MAKE) -j$(shell nproc) sdk

source: defconfig
	$(info -------------------------------- $@)
	$(BR2_MAKE) BR2_DEFCONFIG=$(CAMERA_CONFIG_REAL) source

# build toolchain
toolchain: defconfig
	$(info -------------------------------- $@)
	$(BR2_MAKE) sdk

# flash new uboot image to the camera
upboot_ota: $(U_BOOT_BIN)
	$(info -------------------------------- $@)
	$(SCRIPTS_DIR)/fw_ota.sh $(U_BOOT_BIN) $(CAMERA_IP_ADDRESS)

# flash compiled update image to the camera
update_ota: $(FIRMWARE_BIN_NOBOOT)
	$(info -------------------------------- $@)
	$(SCRIPTS_DIR)/fw_ota.sh $(FIRMWARE_BIN_NOBOOT) $(CAMERA_IP_ADDRESS)

# flash compiled full image to the camera
upgrade_ota: $(FIRMWARE_BIN_FULL)
	$(info -------------------------------- $@)
	$(SCRIPTS_DIR)/fw_ota.sh $(FIRMWARE_BIN_FULL) $(CAMERA_IP_ADDRESS)

# upload firmware to tftp server
upload_tftp: $(FIRMWARE_BIN_FULL)
	$(info -------------------------------- $@)
	busybox tftp -l $(FIRMWARE_BIN_FULL) -r $(FIRMWARE_NAME_FULL) -p $(TFTP_IP_ADDRESS)

### Buildroot

# delete all build/{package} and per-package/{package} files
br-%-dirclean:
	$(info -------------------------------- $@)
	rm -rf $(OUTPUT_DIR)/per-package/$(subst -dirclean,,$(subst br-,,$@)) \
		$(OUTPUT_DIR)/build/$(subst -dirclean,,$(subst br-,,$@))* \
		$(OUTPUT_DIR)/target
	#  \ sed -i /^$(subst -dirclean,,$(subst br-,,$@))/d $(OUTPUT_DIR)/build/packages-file-list.txt

br-%: defconfig
	$(info -------------------------------- $@)
	$(BR2_MAKE) $(subst br-,,$@)

# checkout buidroot submodule
buildroot/Makefile:
	$(info -------------------------------- $@)
	git submodule init
	git submodule update --depth 1 --recursive

# create output directory
$(OUTPUT_DIR)/.keep:
	$(info -------------------------------- $@)
	test -d $(OUTPUT_DIR) || mkdir -p $(OUTPUT_DIR)
	touch $@

# create config partition directory
$(CONFIG_PARTITION_DIR)/.keep:
	$(info -------------------------------- $@)
	test -d $(CONFIG_PARTITION_DIR) || mkdir -p $(CONFIG_PARTITION_DIR)
	touch $@

# configure buildroot for a particular board
$(OUTPUT_DIR)/.config: $(OUTPUT_DIR)/.keep $(CONFIG_PARTITION_DIR)/.keep
	$(info -------------------------------- $@)
	$(FIGLET) "$(BOARD)"
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
	@if [ $(RELEASE) -eq 1 ]; then $(FIGLET) "RELEASE"; else $(FIGLET) "DEVELOPMENT"; fi
	if [ $(RELEASE) -ne 1 ] && [ -f local.fragment ]; then cat local.fragment >>$(OUTPUT_DIR)/.config; fi
	if [ $(RELEASE) -ne 1 ] && [ -f $(BR2_EXTERNAL)/local.mk ]; then cp -f $(BR2_EXTERNAL)/local.mk $(OUTPUT_DIR)/local.mk; fi
	if [ ! -L $(OUTPUT_DIR)/thingino ]; then ln -s $(BR2_EXTERNAL) $(OUTPUT_DIR)/thingino; fi
	cp $(OUTPUT_DIR)/.config $(OUTPUT_DIR)/.config_original
	$(BR2_MAKE) BR2_DEFCONFIG=$(CAMERA_CONFIG_REAL) olddefconfig

$(UB_ENV_FINAL_TXT): $(OUTPUT_DIR)/.config
	$(info -------------------------------- $@)
	if [ -f $(BR2_EXTERNAL)$(shell sed -rn "s/^U_BOOT_ENV_TXT=\"\\\$$\(\w+\)(.+)\"/\1/p" $(OUTPUT_DIR)/.config) ]; then \
		grep -v '^#' $(BR2_EXTERNAL)$(shell sed -rn "s/^U_BOOT_ENV_TXT=\"\\\$$\(\w+\)(.+)\"/\1/p" $(OUTPUT_DIR)/.config) | tee $@; \
		if [ $(RELEASE) -ne 1 ] && [ -f $(BR2_EXTERNAL)/local.uenv.txt ]; then \
			grep -v '^#' $(BR2_EXTERNAL)/local.uenv.txt | while read line; do grep -F -x -q "$$line" $@ || echo "$$line" >> $@; done; \
		fi; \
	fi
	sort -u -o $@ $@
	sed -i '/^\s*$$/d' $@

$(FIRMWARE_BIN_FULL): $(U_BOOT_BIN) $(UB_ENV_BIN) $(CONFIG_BIN) $(KERNEL_BIN) $(ROOTFS_BIN) $(OVERLY_BIN)
	$(info -------------------------------- $@)
	dd if=/dev/zero bs=$(SIZE_8M) skip=0 count=1 status=none | tr '\000' '\377' > $@
	dd if=$(U_BOOT_BIN) bs=$(U_BOOT_BIN_SIZE) seek=$(U_BOOT_OFFSET)B count=1 of=$@ conv=notrunc status=none
	dd if=$(CONFIG_BIN) bs=$(CONFIG_BIN_SIZE) seek=$(CONFIG_OFFSET)B count=1 of=$@ conv=notrunc status=none
	dd if=$(KERNEL_BIN) bs=$(KERNEL_BIN_SIZE) seek=$(KERNEL_OFFSET)B count=1 of=$@ conv=notrunc status=none
	dd if=$(ROOTFS_BIN) bs=$(ROOTFS_BIN_SIZE) seek=$(ROOTFS_OFFSET)B count=1 of=$@ conv=notrunc status=none
	dd if=$(OVERLY_BIN) bs=$(OVERLY_BIN_SIZE) seek=$(OVERLY_OFFSET)B count=1 of=$@ conv=notrunc status=none

$(FIRMWARE_BIN_NOBOOT): $(KERNEL_BIN) $(ROOTFS_BIN) $(OVERLY_BIN)
	$(info -------------------------------- $@)
	dd if=/dev/zero bs=$(FIRMWARE_NOBOOT_SIZE) skip=0 count=1 status=none | tr '\000' '\377' > $@
	dd if=$(KERNEL_BIN) bs=$(KERNEL_BIN_SIZE) seek=0 count=1 of=$@ conv=notrunc status=none
	dd if=$(ROOTFS_BIN) bs=$(ROOTFS_BIN_SIZE) seek=$(KERNEL_PARTITION_SIZE)B count=1 of=$@ conv=notrunc status=none
	dd if=$(OVERLY_BIN) bs=$(OVERLY_BIN_SIZE) seek=$(OVERLY_OFFSET_NOBOOT)B count=1 of=$@ conv=notrunc status=none

$(U_BOOT_BIN):
	$(info -------------------------------- $@)

$(UB_ENV_BIN):
	$(info -------------------------------- $@)
	$(OUTPUT_DIR)/host/bin/mkenvimage -s $(UB_ENV_PARTITION_SIZE) -o $@ $(UB_ENV_FINAL_TXT)

# create config partition image
$(CONFIG_BIN):
	$(info -------------------------------- $@)
	$(OUTPUT_DIR)/host/sbin/mkfs.ext2 \
		-F -b 1024 \
		-d $(CONFIG_PARTITION_DIR) \
		-L config $(CONFIG_BIN) 64K
	$(OUTPUT_DIR)/host/sbin/debugfs -w -R 'rmdir lost+found' $(CONFIG_BIN)
	truncate -s 65536 $(CONFIG_BIN)
# FIXME: future, copy files from overlay/config to CONFIG_PARTITION_DIR before creating image

# rebuild kernel
$(KERNEL_BIN):
	$(info -------------------------------- $@)
	$(BR2_MAKE) linux-rebuild
#	mv -vf $(OUTPUT_DIR)/images/uImage $@

# rebuild rootfs
$(ROOTFS_BIN):
	$(info -------------------------------- $@)
	$(BR2_MAKE) all

# create .tar file of rootfs
$(ROOTFS_TAR):
	$(info -------------------------------- $@)
	$(BR2_MAKE) all

$(OVERLY_BIN): $(U_BOOT_BIN)
	$(info -------------------------------- $@)
	if [ $(OVERLY_PARTITION_SIZE) -lt $(OVERLY_LLIMIT) ]; then $(FIGLET) "OVERLAY IS TOO SMALL"; fi
	if [ -f $(OVERLY_BIN) ]; then rm $(OVERLY_BIN); fi
	$(OUTPUT_DIR)/host/sbin/mkfs.jffs2 --little-endian --squash \
		--root=$(BR2_EXTERNAL)/overlay/upper/ \
		--output=$(OVERLY_BIN) \
		--pad=$(OVERLY_PARTITION_SIZE) \
		--eraseblock=$(OVERLY_ERASEBLOCK_SIZE)
       #	--pagesize=$(ALIGN_BLOCK)

help:
	$(info -------------------------------- $@)
	@echo "\n\
	Usage:\n\
	  make bootstrap      install system deps\n\
	  make update         update local repo from GitHub\n\
	  make                build and pack everything\n\
	  make build          build kernel and rootfs\n\
	  make cleanbuild     build everything from scratch, fast\n\
	  make release        build without local fragments\n\
	  make pack           create firmware images\n\
	  make clean          clean before reassembly\n\
	  make distclean      start building from scratch\n\
	  make rebuild-<pkg>  perform a clean package rebuild for <pkg>\n\
	  make help           print this help\n\
	  \n\
	  make upboot_ota IP=192.168.1.10\n\
	                      upload bootloader to the camera\n\
	                        over network, and flash it\n\n\
	  make update_ota IP=192.168.1.10\n\
	                      upload kernel and roofts to the camera\n\
	                        over network, and flash them\n\n\
	  make upgrade_ota IP=192.168.1.10\n\
	                      upload full firmware image to the camera\n\
	                        over network, and flash it\n\n\
	"
