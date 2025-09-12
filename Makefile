# Thingino Firmware
# https://github.com/themactep/thingino-firmware

BR2_HOSTARCH = $(shell uname -m)
export BR2_HOSTARCH

ifeq ($(__BASH_MAKE_COMPLETION__),1)
	exit
endif

# Run dependency check before doing anything, but skip if WORKFLOW=1 or if .prereqs.done exists
ifeq ($(WORKFLOW),)
ifeq ($(wildcard $(CURDIR)/.prereqs.done),)
	_dep_check := $(shell $(CURDIR)/scripts/dep_check.sh>&2; echo $$?)
	ifneq ($(lastword $(_dep_check)),0)
	$(error Dependency check failed)
	endif
endif
else
$(info Skipping dependency check for workflow)
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

# repo data
GIT_BRANCH := $(shell git rev-parse --abbrev-ref HEAD | tr -d '()' | xargs)
GIT_HASH="$(shell git show -s --format=%H | cut -c1-7)"
GIT_DATE="$(TZ=UTC0 git show --quiet --date='format-local:%Y-%m-%d %H:%M:%S UTC' --format="%cd")"
BUILD_DATE="$(shell env -u SOURCE_DATE_EPOCH TZ=UTC date '+%Y-%m-%d %H:%M:%S %z')"

ifeq ($(GROUP),github)
	CAMERA_SUBDIR := configs/github
else ifeq ($(GROUP),modules)
	CAMERA_SUBDIR := configs/modules
else ifeq ($(GROUP),)
	CAMERA_SUBDIR := configs/cameras
else
	CAMERA_SUBDIR := configs/cameras-$(GROUP)
endif
export CAMERA_SUBDIR

# handle the board
include $(BR2_EXTERNAL)/board.mk

export CAMERA

# working directory - set after CAMERA is defined
ifeq ($(CAMERA),)
# If CAMERA is not defined, use a safe default for exempted targets
ifeq ($(GIT_BRANCH),master)
OUTPUT_DIR ?= $(HOME)/output
else ifeq ($(GIT_BRANCH),)
OUTPUT_DIR ?= $(HOME)/output-junk
else
OUTPUT_DIR ?= $(HOME)/output-$(GIT_BRANCH)
endif
else
ifeq ($(GIT_BRANCH),master)
OUTPUT_DIR ?= $(HOME)/output/$(CAMERA)
else ifeq ($(GIT_BRANCH),)
OUTPUT_DIR ?= $(HOME)/output-junk/$(CAMERA)
else
OUTPUT_DIR ?= $(HOME)/output-$(GIT_BRANCH)/$(CAMERA)
endif
endif
$(info OUTPUT_DIR: $(OUTPUT_DIR))
export OUTPUT_DIR

HOST_DIR = $(OUTPUT_DIR)/host

CONFIG_PARTITION_DIR = $(OUTPUT_DIR)/config
export CONFIG_PARTITION_DIR

STDOUT_LOG ?= $(OUTPUT_DIR)/compilation.log
STDERR_LOG ?= $(OUTPUT_DIR)/compilation-errors.log

# include thingino makefile only when board configuration is available
ifeq ($(SKIP_BOARD_SELECTION),)
include $(BR2_EXTERNAL)/thingino.mk
endif

# hardcoded variables
WGET := wget --quiet --no-verbose --retry-connrefused --continue --timeout=5
RSYNC := rsync --verbose --archive

ifeq ($(shell command -v figlet),)
FIGLET := echo
else
FIGLET := $(shell command -v figlet) -t -f pagga
endif

SIZE_1G := 1073741824
SIZE_512M := 536870912
SIZE_256M := 268435456
SIZE_128M := 134217728
SIZE_32M := 33554432
SIZE_16M := 16777216
SIZE_8M := 8388608
SIZE_320K := 327680
SIZE_256K := 262144
SIZE_224K := 229376
SIZE_192K := 196608
SIZE_128K := 131072
SIZE_64K := 65536
SIZE_32K := 32768
SIZE_16K := 16384
SIZE_8K := 8192
SIZE_4K := 4096

ALIGN_BLOCK := $(SIZE_32K)

U_BOOT_GITHUB_URL := https://github.com/gtxaspec/u-boot-ingenic/releases/download/latest

ifeq ($(BR2_PACKAGE_THINGINO_UBOOT_FORMAT_CUSTOM_NAME),)
U_BOOT_BIN = $(OUTPUT_DIR)/images/u-boot-lzo-with-spl.bin
else
U_BOOT_BIN = $(OUTPUT_DIR)/images/$(patsubst "%",%,$(BR2_PACKAGE_THINGINO_UBOOT_FORMAT_CUSTOM_NAME))
endif

U_BOOT_ENV_TXT = $(OUTPUT_DIR)/uenv.txt
export U_BOOT_ENV_TXT

UB_ENV_BIN = $(OUTPUT_DIR)/images/u-boot-env.bin
CONFIG_BIN := $(OUTPUT_DIR)/images/config.jffs2
KERNEL_BIN := $(OUTPUT_DIR)/images/uImage
ROOTFS_BIN := $(OUTPUT_DIR)/images/rootfs.squashfs
ROOTFS_TAR := $(OUTPUT_DIR)/images/rootfs.tar
EXTRAS_BIN := $(OUTPUT_DIR)/images/extras.jffs2

# TODO: create a full binary file suffixed with the time of the last modification
# to either uboot, kernel, or rootfs
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
EXTRAS_BIN_SIZE = $(shell stat -c%s $(EXTRAS_BIN))

FIRMWARE_BIN_FULL_SIZE = $(shell stat -c%s $(FIRMWARE_BIN_FULL))

U_BOOT_BIN_SIZE_ALIGNED = $(shell echo $$((($(U_BOOT_BIN_SIZE) + $(ALIGN_BLOCK) - 1) / $(ALIGN_BLOCK) * $(ALIGN_BLOCK))))
UB_ENV_BIN_SIZE_ALIGNED = $(shell echo $$((($(UB_ENV_BIN_SIZE) + $(ALIGN_BLOCK) - 1) / $(ALIGN_BLOCK) * $(ALIGN_BLOCK))))
CONFIG_BIN_SIZE_ALIGNED = $(shell echo $$((($(CONFIG_BIN_SIZE) + $(ALIGN_BLOCK) - 1) / $(ALIGN_BLOCK) * $(ALIGN_BLOCK))))
KERNEL_BIN_SIZE_ALIGNED = $(shell echo $$((($(KERNEL_BIN_SIZE) + $(ALIGN_BLOCK) - 1) / $(ALIGN_BLOCK) * $(ALIGN_BLOCK))))
ROOTFS_BIN_SIZE_ALIGNED = $(shell echo $$((($(ROOTFS_BIN_SIZE) + $(ALIGN_BLOCK) - 1) / $(ALIGN_BLOCK) * $(ALIGN_BLOCK))))
EXTRAS_BIN_SIZE_ALIGNED = $(shell echo $$((($(EXTRAS_BIN_SIZE) + $(ALIGN_BLOCK) - 1) / $(ALIGN_BLOCK) * $(ALIGN_BLOCK))))

# fixed size partitions
U_BOOT_PARTITION_SIZE := $(SIZE_256K)
UB_ENV_PARTITION_SIZE := $(SIZE_32K)
CONFIG_PARTITION_SIZE := $(SIZE_224K)
KERNEL_PARTITION_SIZE = $(KERNEL_BIN_SIZE_ALIGNED)
ROOTFS_PARTITION_SIZE = $(ROOTFS_BIN_SIZE_ALIGNED)

FIRMWARE_FULL_SIZE = $(FLASH_SIZE)
FIRMWARE_NOBOOT_SIZE = $(shell echo $$(($(FLASH_SIZE) - $(U_BOOT_PARTITION_SIZE) - $(UB_ENV_PARTITION_SIZE) - $(CONFIG_PARTITION_SIZE))))

# dynamic partitions
EXTRAS_PARTITION_SIZE = $(shell echo $$(($(FLASH_SIZE) - $(EXTRAS_OFFSET))))
EXTRAS_LLIMIT := $(shell echo $$(($(ALIGN_BLOCK) * 5)))

# partition offsets
U_BOOT_OFFSET := 0
UB_ENV_OFFSET = $(shell echo $$(($(U_BOOT_OFFSET) + $(U_BOOT_PARTITION_SIZE))))
CONFIG_OFFSET = $(shell echo $$(($(UB_ENV_OFFSET) + $(UB_ENV_PARTITION_SIZE))))
KERNEL_OFFSET = $(shell echo $$(($(CONFIG_OFFSET) + $(CONFIG_PARTITION_SIZE))))
ROOTFS_OFFSET = $(shell echo $$(($(KERNEL_OFFSET) + $(KERNEL_PARTITION_SIZE))))
EXTRAS_OFFSET = $(shell echo $$(($(ROOTFS_OFFSET) + $(ROOTFS_PARTITION_SIZE))))

# special case with no uboot nor env
EXTRAS_OFFSET_NOBOOT = $(shell echo $$(($(KERNEL_PARTITION_SIZE) + $(ROOTFS_PARTITION_SIZE))))

RELEASE = 0

EDITOR := $(shell which nano vim vi ed 2>/dev/null | head -1)

define edit_file
	$(info -------------------------------- $(1))
	@if [ -z "$(EDITOR)" ]; then \
		echo "No suitable editor found!"; \
		exit 1; \
	else \
		$(EDITOR) $(2); \
	fi
endef

# make command for buildroot
BR2_MAKE = $(MAKE) -C $(BR2_EXTERNAL)/buildroot BR2_EXTERNAL=$(BR2_EXTERNAL) O=$(OUTPUT_DIR) BR2_DL_DIR=$(BR2_DL_DIR)

.PHONY: all bootstrap build build_fast clean clean-nfs-debug cleanbuild defconfig distclean fast \
	help pack release remove_bins repack sdk toolchain update upboot-ota \
	upload_tftp upgrade_ota br-% check-config force-config show-config-deps clean-config

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

# update repo and submodules with buildroot patch management
update:
	$(info -------------------------------- $@)
	@echo "=== UPDATING MAIN REPOSITORY ==="
	git pull --rebase --autostash
	@echo "=== UPDATING SUBMODULES ==="
	git submodule update --init --remote --recursive
	@echo "=== UPDATING BUILDROOT WITH PATCH MANAGEMENT ==="

# install what's needed
bootstrap:
	$(info -------------------------------- $@)
	$(SCRIPTS_DIR)/dep_check.sh

build: $(U_BOOT_ENV_TXT)
	$(info -------------------------------- $@)
	$(BR2_MAKE) all

build_fast: $(U_BOOT_ENV_TXT)
	$(info -------------------------------- $@)
	$(BR2_MAKE) -j$(shell nproc) all

### Configuration

FRAGMENTS = $(shell awk '/FRAG:/ {$$1=$$1;gsub(/^.+:\s*/,"");print}' $(MODULE_CONFIG_REAL))

# Configuration dependency files
CONFIG_DEPS_FILE = $(OUTPUT_DIR)/.config.deps
CONFIG_FRAGMENT_FILES = $(addprefix configs/fragments/,$(addsuffix .fragment,$(FRAGMENTS)))
CONFIG_INPUT_FILES = $(CONFIG_FRAGMENT_FILES) $(MODULE_CONFIG_REAL)
ifneq ($(CAMERA_CONFIG_REAL),$(MODULE_CONFIG_REAL))
CONFIG_INPUT_FILES += $(CAMERA_CONFIG_REAL)
endif
ifeq ($(RELEASE),0)
ifneq ($(wildcard $(BR2_EXTERNAL)/configs/local.fragment),)
CONFIG_INPUT_FILES += $(BR2_EXTERNAL)/configs/local.fragment
endif
ifneq ($(wildcard $(BR2_EXTERNAL)/local.mk),)
CONFIG_INPUT_FILES += $(BR2_EXTERNAL)/local.mk
endif
endif

# Function to check if configuration needs regeneration
define config_needs_regen
$(shell \
	if [ ! -f $(OUTPUT_DIR)/.config ] || [ ! -f $(CONFIG_DEPS_FILE) ]; then \
		echo "yes"; \
	else \
		for file in $(CONFIG_INPUT_FILES); do \
			if [ "$$file" -nt $(OUTPUT_DIR)/.config ]; then \
				echo "yes"; \
				break; \
			fi; \
		done; \
	fi \
)
endef

# Smart configuration check - only regenerate if needed
check-config: buildroot/Makefile
	$(info -------------------------------- $@)
	@if [ "$(call config_needs_regen)" = "yes" ]; then \
		echo "Configuration files have changed, regenerating .config"; \
		$(MAKE) force-config; \
	else \
		echo "Configuration is up to date"; \
	fi

# Force configuration regeneration
force-config: buildroot/Makefile $(OUTPUT_DIR)/.keep $(CONFIG_PARTITION_DIR)/.keep
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
	if [ $(RELEASE) -eq 1 ]; then \
		$(FIGLET) "RELEASE"; \
	else \
		$(FIGLET) "DEVELOPMENT"; \
		if [ -f $(BR2_EXTERNAL)/configs/local.fragment ]; then \
			cat $(BR2_EXTERNAL)/configs/local.fragment >>$(OUTPUT_DIR)/.config; \
		fi; \
		if [ -f $(BR2_EXTERNAL)/local.mk ]; then \
			cp -f $(BR2_EXTERNAL)/local.mk $(OUTPUT_DIR)/local.mk; \
		fi; \
	fi
	if [ ! -L $(OUTPUT_DIR)/thingino ]; then \
		ln -s $(BR2_EXTERNAL) $(OUTPUT_DIR)/thingino; \
	fi
	cp $(OUTPUT_DIR)/.config $(OUTPUT_DIR)/.config_original
	$(BR2_MAKE) BR2_DEFCONFIG=$(CAMERA_CONFIG_REAL) olddefconfig
	# Create dependency tracking file
	@echo "# Configuration dependency tracking file" > $(CONFIG_DEPS_FILE)
	@echo "# Generated on $$(date)" >> $(CONFIG_DEPS_FILE)
	@echo "CONFIG_INPUT_FILES = $(CONFIG_INPUT_FILES)" >> $(CONFIG_DEPS_FILE)
	@for file in $(CONFIG_INPUT_FILES); do \
		if [ -f "$$file" ]; then \
			echo "$$file: $$(stat -c %Y "$$file")" >> $(CONFIG_DEPS_FILE); \
		fi; \
	done

# Configure buildroot for a particular board
defconfig: check-config
	$(info -------------------------------- $@)
	@$(FIGLET) $(CAMERA)
	# Ensure buildroot is properly configured
	$(BR2_MAKE) BR2_DEFCONFIG=$(CAMERA_CONFIG_REAL) olddefconfig

edit:
	@bash -c 'while true; do \
		CHOICE=$$(dialog --keep-tite --colors --title "Edit Menu" --menu "Choose an option to edit:" 16 60 10 \
			"1" "Camera Config (edit-defconfig)" \
			"2" "Module Config (edit-module)" \
			"3" "System Config (edit-config)" \
			"4" "Camera U-Boot Environment (edit-uenv)" \
			"" "━━━━━━━━━ LOCAL OVERRIDES ━━━━━━━━━" \
			"5" "Local Fragment (edit-localfragment)" \
			"6" "Local Config (edit-localconfig)" \
			"7" "Local Makefile (edit-localmk)" \
			"8" "Local U-Boot Evironment (edit-localuenv)" 2>&1 >/dev/tty) || exit 0; \
		\
		[ -z "$$CHOICE" ] && continue; \
		\
		case "$$CHOICE" in \
			"1") FILE="$(CAMERA_CONFIG_REAL)" ;; \
			"2") FILE="$(MODULE_CONFIG_REAL)" ;; \
			"3") FILE="$(BR2_EXTERNAL)/$(CAMERA_SUBDIR)/$(CAMERA)/$(CAMERA).config" ;; \
			"4") FILE="$(BR2_EXTERNAL)/$(CAMERA_SUBDIR)/$(CAMERA)/$(CAMERA).uenv.txt" ;; \
			"5") FILE="$(BR2_EXTERNAL)/configs/local.fragment" ;; \
			"6") FILE="$(BR2_EXTERNAL)/configs/local.config" ;; \
			"7") FILE="$(BR2_EXTERNAL)/local.mk" ;; \
			"8") FILE="$(BR2_EXTERNAL)/configs/local.uenv.txt" ;; \
			*) echo "Invalid option"; continue ;; \
		esac; \
		\
		[ -z "$(EDITOR)" ] && { echo "No suitable editor found!"; exit 1; } || { $(EDITOR) "$$FILE"; break; }; \
	done'

edit-defconfig:
	$(call edit_file,$@,$(CAMERA_CONFIG_REAL))

edit-module:
	$(call edit_file,$@,$(MODULE_CONFIG_REAL))

edit-config:
	$(call edit_file,$@,$(BR2_EXTERNAL)/$(CAMERA_SUBDIR)/$(CAMERA)/$(CAMERA).config)

edit-uenv:
	$(call edit_file,$@,$(BR2_EXTERNAL)/$(CAMERA_SUBDIR)/$(CAMERA)/$(CAMERA).uenv.txt)

edit-localmk:
	$(call edit_file,$@,$(BR2_EXTERNAL)/local.mk)

edit-localconfig:
	$(call edit_file,$@,$(BR2_EXTERNAL)/configs/local.config)

edit-localfragment:
	$(call edit_file,$@,$(BR2_EXTERNAL)/configs/local.fragment)

edit-localuenv:
	$(call edit_file,$@,$(BR2_EXTERNAL)/configs/local.uenv.txt)

# Configuration debugging and maintenance targets
show-config-deps:
	$(info -------------------------------- $@)
	@echo "Configuration input files:"
	@for file in $(CONFIG_INPUT_FILES); do \
		if [ -f "$$file" ]; then \
			echo "  $$file (exists, modified: $$(stat -c %Y "$$file"))"; \
		else \
			echo "  $$file (missing)"; \
		fi; \
	done
	@if [ -f $(CONFIG_DEPS_FILE) ]; then \
		echo ""; \
		echo "Current dependency tracking:"; \
		cat $(CONFIG_DEPS_FILE); \
	else \
		echo ""; \
		echo "No dependency tracking file found at $(CONFIG_DEPS_FILE)"; \
	fi

clean-config:
	$(info -------------------------------- $@)
	rm -f $(OUTPUT_DIR)/.config $(CONFIG_DEPS_FILE) $(OUTPUT_DIR)/.config_original

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

# Clean camera-specific NFS debug artifacts
clean-nfs-debug:
	$(info -------------------------------- $@)
	@if [ -z "$(CAMERA)" ] || [ "$(CAMERA)" = "" ]; then \
		echo "CAMERA variable not defined, skipping NFS debug cleanup"; \
	elif [ ! -f "$(OUTPUT_DIR)/.config" ]; then \
		echo "Configuration file not found, skipping NFS debug cleanup"; \
	else \
		NFS_PATH=$$(grep '^BR2_THINGINO_NFS=' "$(OUTPUT_DIR)/.config" 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo ""); \
		DEBUG_ENABLED=$$(grep '^BR2_PACKAGE_PRUDYNT_T_DEBUG=y' "$(OUTPUT_DIR)/.config" 2>/dev/null || echo ""); \
		DEV_PACKAGES_ENABLED=$$(grep '^BR2_THINGINO_DEV_PACKAGES=y' "$(OUTPUT_DIR)/.config" 2>/dev/null || echo ""); \
		\
		if [ -n "$$DEBUG_ENABLED" ] && [ -n "$$DEV_PACKAGES_ENABLED" ] && [ -n "$$NFS_PATH" ] && [ "$$NFS_PATH" != "" ]; then \
			CAMERA_NFS_DIR="$$NFS_PATH/$(CAMERA)"; \
			if [ -d "$$CAMERA_NFS_DIR" ]; then \
				echo "Removing camera-specific NFS debug artifacts: $$CAMERA_NFS_DIR"; \
				rm -rf "$$CAMERA_NFS_DIR"; \
				echo "NFS debug artifacts cleaned for camera: $(CAMERA)"; \
			else \
				echo "NFS debug directory does not exist: $$CAMERA_NFS_DIR (skipping)"; \
			fi; \
		else \
			if [ -z "$$DEBUG_ENABLED" ]; then \
				echo "Debug builds not enabled, skipping NFS debug cleanup"; \
			elif [ -z "$$DEV_PACKAGES_ENABLED" ]; then \
				echo "Development packages not enabled, skipping NFS debug cleanup"; \
			elif [ -z "$$NFS_PATH" ] || [ "$$NFS_PATH" = "" ]; then \
				echo "NFS path not configured, skipping NFS debug cleanup"; \
			fi; \
		fi; \
	fi

# remove target/ directory
clean: clean-nfs-debug
	$(info -------------------------------- $@)
	rm -rf $(OUTPUT_DIR)/target
	rm -rf $(OUTPUT_DIR)/config
	rm -rf $(OUTPUT_DIR)/extras
	rm -f $(FIRMWARE_BIN_FULL) $(FIRMWARE_BIN_FULL).sha256sum
	rm -f $(FIRMWARE_BIN_NOBOOT) $(FIRMWARE_BIN_NOBOOT).sha256sum
	rm -f $(ROOTFS_BIN) $(ROOTFS_TAR) $(EXTRAS_BIN) $(CONFIG_BIN)
#	$(UB_ENV_BIN) $(KERNEL_BIN)


# remove all build files
distclean: clean-nfs-debug
	$(info -------------------------------- $@)
	if [ -d "$(OUTPUT_DIR)" ]; then rm -rf $(OUTPUT_DIR); fi

# assemble final images
pack: $(FIRMWARE_BIN_FULL) $(FIRMWARE_BIN_NOBOOT)
	$(info -------------------------------- $@)
	$(info ALIGNMENT: $(ALIGN_BLOCK))
	$(info  )
	$(info $(shell printf "%-7s | %8s | %8s | %8s | %8s | %8s | %8s |" NAME OFFSET PT_SIZE CONTENT ALIGNED END LOSS))
	$(info $(shell printf "%-7s | %8d | %8d | %8d | %8d | %8d | %8d |" U_BOOT $(U_BOOT_OFFSET) $(U_BOOT_PARTITION_SIZE) $(U_BOOT_BIN_SIZE) $(U_BOOT_BIN_SIZE_ALIGNED) $$(($(U_BOOT_OFFSET) + $(U_BOOT_BIN_SIZE_ALIGNED))) $$(($(U_BOOT_PARTITION_SIZE) - $(U_BOOT_BIN_SIZE_ALIGNED))) ))
	$(info $(shell printf "%-7s | %8d | %8d | %8d | %8d | %8d | %8d |" UB_ENV $(UB_ENV_OFFSET) $(UB_ENV_PARTITION_SIZE) $(UB_ENV_BIN_SIZE) $(UB_ENV_BIN_SIZE_ALIGNED) $$(($(UB_ENV_OFFSET) + $(UB_ENV_BIN_SIZE_ALIGNED))) $$(($(UB_ENV_PARTITION_SIZE) - $(UB_ENV_BIN_SIZE_ALIGNED))) ))
	$(info $(shell printf "%-7s | %8d | %8d | %8d | %8d | %8d | %8d |" CONFIG $(CONFIG_OFFSET) $(CONFIG_PARTITION_SIZE) $(CONFIG_BIN_SIZE) $(CONFIG_BIN_SIZE_ALIGNED) $$(($(CONFIG_OFFSET) + $(CONFIG_BIN_SIZE_ALIGNED))) $$(($(CONFIG_PARTITION_SIZE) - $(CONFIG_BIN_SIZE_ALIGNED))) ))
	$(info $(shell printf "%-7s | %8d | %8d | %8d | %8d | %8d | %8d |" KERNEL $(KERNEL_OFFSET) $(KERNEL_PARTITION_SIZE) $(KERNEL_BIN_SIZE) $(KERNEL_PARTITION_SIZE) $$(($(KERNEL_OFFSET) + $(KERNEL_PARTITION_SIZE))) $$(($(KERNEL_PARTITION_SIZE) - $(KERNEL_PARTITION_SIZE))) ))
	$(info $(shell printf "%-7s | %8d | %8d | %8d | %8d | %8d | %8d |" ROOTFS $(ROOTFS_OFFSET) $(ROOTFS_PARTITION_SIZE) $(ROOTFS_BIN_SIZE) $(ROOTFS_PARTITION_SIZE) $$(($(ROOTFS_OFFSET) + $(ROOTFS_PARTITION_SIZE))) $$(($(ROOTFS_PARTITION_SIZE) - $(ROOTFS_PARTITION_SIZE))) ))
	$(info $(shell printf "%-7s | %8d | %8d | %8d | %8d | %8d | %8d |" OVERLAY $(EXTRAS_OFFSET) $(EXTRAS_PARTITION_SIZE) $(EXTRAS_BIN_SIZE) $(EXTRAS_BIN_SIZE_ALIGNED) $$(($(EXTRAS_OFFSET) + $(EXTRAS_BIN_SIZE_ALIGNED))) $$(($(EXTRAS_PARTITION_SIZE) - $(EXTRAS_BIN_SIZE_ALIGNED))) ))
	$(info  )
	$(info $(shell printf "%-7s | %8s | %8s | %8s | %8s | %8s | %8s |" NAME OFFSET PT_SIZE CONTENT ALIGNED END LOSS))
	$(info $(shell printf "%-7s | %08X | %08X | %08X | %08X | %08X | %08X |" U_BOOT $(U_BOOT_OFFSET) $(U_BOOT_PARTITION_SIZE) $(U_BOOT_BIN_SIZE) $(U_BOOT_BIN_SIZE_ALIGNED) $$(($(U_BOOT_OFFSET) + $(U_BOOT_BIN_SIZE_ALIGNED))) $$(($(U_BOOT_PARTITION_SIZE) - $(U_BOOT_BIN_SIZE_ALIGNED))) ))
	$(info $(shell printf "%-7s | %08X | %08X | %08X | %08X | %08X | %08X |" ENV $(UB_ENV_OFFSET) $(UB_ENV_PARTITION_SIZE) $(UB_ENV_BIN_SIZE) $(UB_ENV_BIN_SIZE_ALIGNED) $$(($(UB_ENV_OFFSET) + $(UB_ENV_BIN_SIZE_ALIGNED))) $$(($(UB_ENV_PARTITION_SIZE) - $(UB_ENV_BIN_SIZE_ALIGNED))) ))
	$(info $(shell printf "%-7s | %08X | %08X | %08X | %08X | %08X | %08X |" CONFIG $(CONFIG_OFFSET) $(CONFIG_PARTITION_SIZE) $(CONFIG_BIN_SIZE) $(CONFIG_BIN_SIZE_ALIGNED) $$(($(CONFIG_OFFSET) + $(CONFIG_BIN_SIZE_ALIGNED))) $$(($(CONFIG_PARTITION_SIZE) - $(CONFIG_BIN_SIZE_ALIGNED))) ))
	$(info $(shell printf "%-7s | %08X | %08X | %08X | %08X | %08X | %08X |" KERNEL $(KERNEL_OFFSET) $(KERNEL_PARTITION_SIZE) $(KERNEL_BIN_SIZE) $(KERNEL_PARTITION_SIZE) $$(($(KERNEL_OFFSET) + $(KERNEL_PARTITION_SIZE))) $$(($(KERNEL_PARTITION_SIZE) - $(KERNEL_PARTITION_SIZE))) ))
	$(info $(shell printf "%-7s | %08X | %08X | %08X | %08X | %08X | %08X |" ROOTFS $(ROOTFS_OFFSET) $(ROOTFS_PARTITION_SIZE) $(ROOTFS_BIN_SIZE) $(ROOTFS_PARTITION_SIZE) $$(($(ROOTFS_OFFSET) + $(ROOTFS_PARTITION_SIZE))) $$(($(ROOTFS_PARTITION_SIZE) - $(ROOTFS_PARTITION_SIZE))) ))
	$(info $(shell printf "%-7s | %08X | %08X | %08X | %08X | %08X | %08X |" OVERLAY $(EXTRAS_OFFSET) $(EXTRAS_PARTITION_SIZE) $(EXTRAS_BIN_SIZE) $(EXTRAS_BIN_SIZE_ALIGNED) $$(($(EXTRAS_OFFSET) + $(EXTRAS_BIN_SIZE_ALIGNED))) $$(($(EXTRAS_PARTITION_SIZE) - $(EXTRAS_BIN_SIZE_ALIGNED))) ))
	$(info  )

	if [ $(FIRMWARE_BIN_FULL_SIZE) -gt $(FIRMWARE_FULL_SIZE) ]; then $(FIGLET) "OVERSIZE"; fi
	rm -f $(FIRMWARE_BIN_FULL).sha256sum
	echo "$(shell echo \# $(CAMERA))" >> $(FIRMWARE_BIN_FULL).sha256sum
	echo "# ${GIT_BRANCH}+${GIT_HASH}, ${BUILD_DATE}" >> "$(FIRMWARE_BIN_FULL).sha256sum"
	sha256sum $(FIRMWARE_BIN_FULL) | awk '{print $$1 "  " filename}' filename="$(FIRMWARE_NAME_FULL)" >> $(FIRMWARE_BIN_FULL).sha256sum

	rm -f $(FIRMWARE_BIN_NOBOOT).sha256sum
	echo "$(shell echo \# $(CAMERA))" >> $(FIRMWARE_BIN_NOBOOT).sha256sum
	echo "# ${GIT_BRANCH}+${GIT_HASH}, ${BUILD_DATE}" >> "$(FIRMWARE_BIN_NOBOOT).sha256sum"
	sha256sum $(FIRMWARE_BIN_NOBOOT) | awk '{print $$1 "  " filename}' filename="$(FIRMWARE_NAME_NOBOOT)" >> $(FIRMWARE_BIN_NOBOOT).sha256sum
	@$(FIGLET) $(CAMERA)
	@$(FIGLET) "FINE"
	@echo "--------------------------------"
	@echo "Full Image:"
	@echo "$(FIRMWARE_BIN_FULL)"
	@echo "Update Image:"
	@echo "$(FIRMWARE_BIN_NOBOOT)"

# rebuild a package with smart configuration check
rebuild-%: check-config
	$(info -------------------------------- $@)
	$(BR2_MAKE) $(subst rebuild-,,$@)-dirclean $(subst rebuild-,,$@)

remove_bins:
	$(info -------------------------------- $@)
	rm -f $(KERNEL_BIN) $(ROOTFS_BIN) $(EXTRAS_BIN)

repack: remove_bins pack
	$(info -------------------------------- $@)

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

# download buildroot cache bundle from latest github release
download-cache:
	$(info -------------------------------- $@)
	BR2_EXTERNAL=$(CURDIR) BR2_DL_DIR=$(BR2_DL_DIR) $(CURDIR)/scripts/dl_buildroot_cache.sh

### Buildroot

# delete all build/{package} and per-package/{package} files
br-%-dirclean:
	$(info -------------------------------- $@)
	rm -rf $(OUTPUT_DIR)/per-package/$(subst -dirclean,,$(subst br-,,$@)) \
		$(OUTPUT_DIR)/build/$(subst -dirclean,,$(subst br-,,$@))* \
		$(OUTPUT_DIR)/target
	#  \ sed -i /^$(subst -dirclean,,$(subst br-,,$@))/d $(OUTPUT_DIR)/build/packages-file-list.txt

br-%: check-config
	$(info -------------------------------- $@)
	$(BR2_MAKE) $(subst br-,,$@)

# checkout buidroot submodule
buildroot/Makefile:
	$(info -------------------------------- $@)
	git submodule init
	git submodule update --remote --recursive

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

$(U_BOOT_ENV_TXT): $(OUTPUT_DIR)/.config
	$(info -------------------------------- $@)
	touch $@
	grep -v '^#' $(BR2_EXTERNAL)/configs/common.uenv.txt | awk NF | tee -a $@
	grep -v '^#' $(BR2_EXTERNAL)/$(CAMERA_SUBDIR)/$(CAMERA)/$(CAMERA).uenv.txt | awk NF | tee -a $@
	grep -v '^#' $(BR2_EXTERNAL)/configs/local.uenv.txt | awk NF | tee -a $@
	sort -u -o $@ $@

$(FIRMWARE_BIN_FULL): $(U_BOOT_BIN) $(UB_ENV_BIN) $(CONFIG_BIN) $(KERNEL_BIN) $(ROOTFS_BIN) $(EXTRAS_BIN)
	$(info -------------------------------- $@)
	dd if=/dev/zero bs=$(FIRMWARE_FULL_SIZE) skip=0 count=1 status=none | tr '\000' '\377' > $@
	dd if=$(U_BOOT_BIN) bs=$(U_BOOT_BIN_SIZE) seek=$(U_BOOT_OFFSET)B count=1 of=$@ conv=notrunc status=none
	dd if=$(CONFIG_BIN) bs=$(CONFIG_BIN_SIZE) seek=$(CONFIG_OFFSET)B count=1 of=$@ conv=notrunc status=none
	dd if=$(KERNEL_BIN) bs=$(KERNEL_BIN_SIZE) seek=$(KERNEL_OFFSET)B count=1 of=$@ conv=notrunc status=none
	dd if=$(ROOTFS_BIN) bs=$(ROOTFS_BIN_SIZE) seek=$(ROOTFS_OFFSET)B count=1 of=$@ conv=notrunc status=none
	dd if=$(EXTRAS_BIN) bs=$(EXTRAS_BIN_SIZE) seek=$(EXTRAS_OFFSET)B count=1 of=$@ conv=notrunc status=none

$(FIRMWARE_BIN_NOBOOT): $(FIRMWARE_BIN_FULL)
	$(info -------------------------------- $@)
	dd if=$(FIRMWARE_BIN_FULL) of=$@ bs=$(FIRMWARE_NOBOOT_SIZE) count=1 skip=$(KERNEL_OFFSET)B

$(U_BOOT_BIN):
	$(info -------------------------------- $@)

$(UB_ENV_BIN):
	$(info -------------------------------- $@)
	$(HOST_DIR)/bin/mkenvimage -s $(UB_ENV_PARTITION_SIZE) -o $@ $(U_BOOT_ENV_TXT)

# create config partition image
$(CONFIG_BIN): $(CONFIG_PARTITION_DIR)/.keep
	$(info -------------------------------- $@)
	# remove older image if present
	if [ -f $@ ]; then rm $@; fi
	# syncronize overlay files
	$(RSYNC) --delete $(BR2_EXTERNAL)/overlay/config/ $(CONFIG_PARTITION_DIR)/
	$(RSYNC) --delete $(BR2_EXTERNAL)/overlay/upper/ $(CONFIG_PARTITION_DIR)/
	# delete stub files
	find $(CONFIG_PARTITION_DIR)/ -name ".*keep" -o -name ".empty" -delete
	# pack the config partition image
	$(HOST_DIR)/sbin/mkfs.jffs2 --little-endian --squash --output=$@ --root=$(CONFIG_PARTITION_DIR)/ \
		--pad=$(CONFIG_PARTITION_SIZE) --eraseblock=$(ALIGN_BLOCK)

# create extras partition image
$(EXTRAS_BIN): $(U_BOOT_BIN)
	$(info -------------------------------- $@)
	# complain if there is not enough space for extras partition
	if [ $(EXTRAS_PARTITION_SIZE) -lt $(EXTRAS_LLIMIT) ]; then \
		$(FIGLET) "EXTRAS PARTITION IS TOO SMALL"; \
	fi
	# remove older image if present
	if [ -f $@ ]; then rm $@; fi
	# extract /opt/ from target rootfs to a separare directory
	# NB! no deletion here. manually remove files /extras/ or use `make cleanbuild`
	$(RSYNC) $(OUTPUT_DIR)/target/opt/ $(OUTPUT_DIR)/extras/
	# empty /opt/ in the rootfs
	rm -rf $(OUTPUT_DIR)/target/opt/*
	# copy common files
	$(RSYNC) $(BR2_EXTERNAL)/overlay/opt/ $(OUTPUT_DIR)/extras/
	# pack the extras partition image
	$(HOST_DIR)/sbin/mkfs.jffs2 --little-endian --squash --output=$@ --root=$(OUTPUT_DIR)/extras/ \
		--pad=$(EXTRAS_PARTITION_SIZE) --eraseblock=$(ALIGN_BLOCK)

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

help:
	$(info -------------------------------- $@)
	@echo "\n\
	Usage:\n\
	  make bootstrap      install system deps\n\
	  make update         update local repo and submodules (excludes buildroot)\n\
	  make                edit configurations\n\
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
	Configuration Management:\n\
	  make defconfig      configure buildroot (auto-detects changes)\n\
	  make check-config   check if configuration needs regeneration\n\
	  make force-config   force configuration regeneration\n\
	  make show-config-deps  show configuration dependencies\n\
	  make clean-config   remove configuration files\n\
	  \n\
	Buildroot Submodule Management:\n\
	  make update-buildroot     update buildroot submodule with patch management\n\
	  make reset-buildroot      reset buildroot to clean upstream state\n\
	  scripts/update_buildroot.sh  advanced buildroot update with options\n\
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
