# Thingino Firmware
# https://github.com/themactep/thingino-firmware

include Makefile.guided

# Ensure default target builds firmware rather than guided placeholder
.DEFAULT_GOAL := all

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
IP ?=

# TFTP server IP address to upload compiled images to (leave empty to disable TFTP copy)
TFTP_IP_ADDRESS ?=
# TFTP server root directory for local server
TFTP_ROOT ?= /srv/tftp

# project directories
BR2_EXTERNAL := $(CURDIR)
SCRIPTS_DIR := $(BR2_EXTERNAL)/scripts

# Buildroot downloads directory
# can be reused from environment, just export the value:
# export BR2_DL_DIR=/path/to/your/local/storage
BR2_DL_DIR ?= $(BR2_EXTERNAL)/dl

THINGINO_USER_DIR ?= $(BR2_EXTERNAL)/user
export THINGINO_USER_DIR
THINGINO_USER_COMMON_DIR := $(THINGINO_USER_DIR)/common

# repo data
GIT_BRANCH := $(shell git rev-parse --abbrev-ref HEAD | tr -d '()' | xargs)
GIT_HASH = "$(shell git show -s --format=%H | cut -c1-7)"
GIT_DATE = "$(TZ=UTC0 git show --quiet --date='format-local:%Y-%m-%d %H:%M:%S UTC' --format="%cd")"
BUILD_DATE = "$(shell env -u SOURCE_DATE_EPOCH TZ=UTC date '+%Y-%m-%d %H:%M:%S %z')"

ifeq ($(GROUP),github)
CAMERA_SUBDIR := configs/github
else ifeq ($(GROUP),)
CAMERA_SUBDIR := configs/cameras
else
CAMERA_SUBDIR := configs/cameras-$(GROUP)
endif
export CAMERA_SUBDIR

# Support BOARD as an alias for CAMERA (for backward compatibility with workflows)
ifdef BOARD
CAMERA ?= $(BOARD)
endif

# handle the board
include $(BR2_EXTERNAL)/board.mk

export CAMERA

CAMERA_IP_ADDRESS := $(strip $(IP))
IP_OUTPUT_TAG := $(if $(CAMERA_IP_ADDRESS),$(shell printf '%s' "$(CAMERA_IP_ADDRESS)" | sed 's/[^A-Za-z0-9._-]/_/g'))

ifdef CAMERA
THINGINO_USER_CAMERA_DIR := $(THINGINO_USER_DIR)/$(CAMERA)
ifneq ($(CAMERA_IP_ADDRESS),)
THINGINO_USER_DEVICE_DIR := $(THINGINO_USER_CAMERA_DIR)/$(CAMERA_IP_ADDRESS)
endif
endif

THINGINO_USER_FRAGMENT_FILES := $(wildcard $(THINGINO_USER_COMMON_DIR)/local.fragment)
THINGINO_USER_MK_FILES := $(wildcard $(THINGINO_USER_COMMON_DIR)/local.mk)
THINGINO_USER_JSON_FILES := $(wildcard $(THINGINO_USER_COMMON_DIR)/thingino.json)
THINGINO_USER_MOTORS_JSON_FILES := $(wildcard $(THINGINO_USER_COMMON_DIR)/motors.json)
THINGINO_USER_UENV_FILES := $(wildcard $(THINGINO_USER_COMMON_DIR)/local.uenv.txt)
THINGINO_USER_OVERLAY_DIRS := $(wildcard $(THINGINO_USER_COMMON_DIR)/overlay)
THINGINO_USER_OPT_DIRS := $(wildcard $(THINGINO_USER_COMMON_DIR)/opt)

ifdef THINGINO_USER_CAMERA_DIR
THINGINO_USER_FRAGMENT_FILES += $(wildcard $(THINGINO_USER_CAMERA_DIR)/local.fragment)
THINGINO_USER_MK_FILES += $(wildcard $(THINGINO_USER_CAMERA_DIR)/local.mk)
THINGINO_USER_JSON_FILES += $(wildcard $(THINGINO_USER_CAMERA_DIR)/thingino.json)
THINGINO_USER_MOTORS_JSON_FILES += $(wildcard $(THINGINO_USER_CAMERA_DIR)/motors.json)
THINGINO_USER_UENV_FILES += $(wildcard $(THINGINO_USER_CAMERA_DIR)/local.uenv.txt)
THINGINO_USER_OVERLAY_DIRS += $(wildcard $(THINGINO_USER_CAMERA_DIR)/overlay)
THINGINO_USER_OPT_DIRS += $(wildcard $(THINGINO_USER_CAMERA_DIR)/opt)
endif

ifdef THINGINO_USER_DEVICE_DIR
THINGINO_USER_FRAGMENT_FILES += $(wildcard $(THINGINO_USER_DEVICE_DIR)/local.fragment)
THINGINO_USER_MK_FILES += $(wildcard $(THINGINO_USER_DEVICE_DIR)/local.mk)
THINGINO_USER_JSON_FILES += $(wildcard $(THINGINO_USER_DEVICE_DIR)/thingino.json)
THINGINO_USER_MOTORS_JSON_FILES += $(wildcard $(THINGINO_USER_DEVICE_DIR)/motors.json)
THINGINO_USER_UENV_FILES += $(wildcard $(THINGINO_USER_DEVICE_DIR)/local.uenv.txt)
THINGINO_USER_OVERLAY_DIRS += $(wildcard $(THINGINO_USER_DEVICE_DIR)/overlay)
THINGINO_USER_OPT_DIRS += $(wildcard $(THINGINO_USER_DEVICE_DIR)/opt)
endif

export THINGINO_USER_COMMON_DIR
export THINGINO_USER_CAMERA_DIR
export THINGINO_USER_DEVICE_DIR
export THINGINO_USER_FRAGMENT_FILES
export THINGINO_USER_MK_FILES
export THINGINO_USER_JSON_FILES
export THINGINO_USER_MOTORS_JSON_FILES
export THINGINO_USER_UENV_FILES
export THINGINO_USER_OVERLAY_DIRS
export THINGINO_USER_OPT_DIRS

# Resolve toolchain fragment from split boolean selections in defconfig.
TOOLCHAIN_TYPE_RAW := $(if $(CAMERA_CONFIG_REAL),$(strip $(shell sed -n 's/^BR2_THINGINO_TOOLCHAIN_TYPE_\([A-Z0-9_]*\)=y/\1/p' $(CAMERA_CONFIG_REAL) | tail -n 1)))
TOOLCHAIN_GCC_RAW := $(if $(CAMERA_CONFIG_REAL),$(strip $(shell sed -n 's/^BR2_THINGINO_TOOLCHAIN_GCC_\([0-9][0-9]*\)=y/\1/p' $(CAMERA_CONFIG_REAL) | tail -n 1)))
TOOLCHAIN_LIBC_RAW := $(if $(CAMERA_CONFIG_REAL),$(strip $(shell sed -n 's/^BR2_THINGINO_TOOLCHAIN_LIBC_\([A-Z0-9_]*\)=y/\1/p' $(CAMERA_CONFIG_REAL) | tail -n 1)))

TOOLCHAIN_TYPE_RAW := $(if $(TOOLCHAIN_TYPE_RAW),$(TOOLCHAIN_TYPE_RAW),EXTERNAL)
TOOLCHAIN_GCC_RAW := $(if $(TOOLCHAIN_GCC_RAW),$(TOOLCHAIN_GCC_RAW),15)
TOOLCHAIN_LIBC_RAW := $(if $(TOOLCHAIN_LIBC_RAW),$(TOOLCHAIN_LIBC_RAW),MUSL)

TOOLCHAIN_TYPE_TAG := $(if $(filter BUILDROOT,$(TOOLCHAIN_TYPE_RAW)),br,$(if $(filter EXTERNAL,$(TOOLCHAIN_TYPE_RAW)),ext,$(if $(filter LOCAL,$(TOOLCHAIN_TYPE_RAW)),loc,ext)))
TOOLCHAIN_LIBC_TAG := $(shell echo "$(TOOLCHAIN_LIBC_RAW)" | tr 'A-Z' 'a-z')
TOOLCHAIN_FRAGMENT_FILE := configs/fragments/toolchain/$(TOOLCHAIN_TYPE_TAG)-gcc$(TOOLCHAIN_GCC_RAW)-$(TOOLCHAIN_LIBC_TAG).fragment

ifneq ($(CAMERA_CONFIG_REAL),)
ifndef TOOLCHAIN_LIBC
TOOLCHAIN_LIBC := $(if $(TOOLCHAIN_LIBC_TAG),$(TOOLCHAIN_LIBC_TAG),musl)
endif
export TOOLCHAIN_LIBC
$(info TOOLCHAIN_LIBC: $(TOOLCHAIN_LIBC))
endif

# working directory - set after CAMERA is defined
OUTPUT_ROOT_DIR ?= $(BR2_EXTERNAL)/output
OUTPUT_BASE_DIR = $(OUTPUT_ROOT_DIR)/$(GIT_BRANCH)/$(CAMERA)-$(KERNEL_VERSION)-$(TOOLCHAIN_LIBC)
ifeq ($(SKIP_CAMERA_SELECTION),)
OUTPUT_DIR ?= $(OUTPUT_BASE_DIR)$(if $(IP_OUTPUT_TAG),-$(IP_OUTPUT_TAG))
else
OUTPUT_DIR ?= $(OUTPUT_ROOT_DIR)/$(GIT_BRANCH)
endif
export OUTPUT_DIR

GENERIC_OUTPUT_DIR = $(OUTPUT_BASE_DIR)

HOST_DIR = $(OUTPUT_DIR)/host

CONFIG_PARTITION_DIR = $(OUTPUT_DIR)/config
export CONFIG_PARTITION_DIR

# include thingino makefile only when board configuration is available
ifeq ($(SKIP_CAMERA_SELECTION),)
include $(BR2_EXTERNAL)/thingino.mk
endif

$(info OUTPUT_DIR: $(OUTPUT_DIR))

# hardcoded variables
WGET := wget --quiet --no-verbose --retry-connrefused --continue --timeout=5
RSYNC := rsync --verbose --archive

ORANGE := printf '\033[1;38;5;214m%s\033[0m\n'
TEAL := printf '\033[1;38;5;30m%s\033[0m\n'
RED := printf '\033[1;38;5;160m%s\033[0m\n'

ALIGN_BLOCK := 32768

U_BOOT_GITHUB_URL := https://github.com/gtxaspec/u-boot-ingenic/releases/download/latest

ifeq ($(BR2_PACKAGE_THINGINO_UBOOT_FORMAT_CUSTOM_NAME),)
U_BOOT_BIN = $(OUTPUT_DIR)/images/u-boot-lzo-with-spl.bin
GENERIC_U_BOOT_BIN = $(GENERIC_OUTPUT_DIR)/images/u-boot-lzo-with-spl.bin
else
U_BOOT_BIN = $(OUTPUT_DIR)/images/$(patsubst "%",%,$(BR2_PACKAGE_THINGINO_UBOOT_FORMAT_CUSTOM_NAME))
GENERIC_U_BOOT_BIN = $(GENERIC_OUTPUT_DIR)/images/$(patsubst "%",%,$(BR2_PACKAGE_THINGINO_UBOOT_FORMAT_CUSTOM_NAME))
endif

U_BOOT_ENV_TXT = $(OUTPUT_DIR)/uenv.txt
export U_BOOT_ENV_TXT

ifeq ($(SKIP_CAMERA_SELECTION),)
FLASH_SIZE_KB  := $(shell echo $$(($(FLASH_SIZE_MB) * 1024)))
FLASH_SIZE     := $(shell echo $$((($(FLASH_SIZE_KB) * 1024))))
FLASH_SIZE_HEX := $(shell printf '0x%x' $(FLASH_SIZE))

# fixed size partitions
U_BOOT_SIZE_KB := 256
UB_ENV_SIZE_KB := 32
CONFIG_SIZE_KB := 224

UB_ENV_BIN := $(OUTPUT_DIR)/images/u-boot-env.bin
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
GENERIC_FIRMWARE_BIN_FULL := $(GENERIC_OUTPUT_DIR)/images/$(FIRMWARE_NAME_FULL)
GENERIC_FIRMWARE_BIN_NOBOOT := $(GENERIC_OUTPUT_DIR)/images/$(FIRMWARE_NAME_NOBOOT)

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
U_BOOT_PARTITION_SIZE := $(shell echo $$(($(U_BOOT_SIZE_KB) * 1024)))
UB_ENV_PARTITION_SIZE := $(shell echo $$(($(UB_ENV_SIZE_KB) * 1024)))
CONFIG_PARTITION_SIZE := $(shell echo $$(($(CONFIG_SIZE_KB) * 1024)))
KERNEL_PARTITION_SIZE = $(KERNEL_BIN_SIZE_ALIGNED)
ROOTFS_PARTITION_SIZE = $(ROOTFS_BIN_SIZE_ALIGNED)

export U_BOOT_PARTITION_SIZE
export UB_ENV_PARTITION_SIZE
export CONFIG_PARTITION_SIZE
export ALIGN_BLOCK

# Partition sizes in KB for mtdparts
KERNEL_SIZE_KB  = $(shell echo $$(($(KERNEL_PARTITION_SIZE) / 1024)))
ROOTFS_SIZE_KB  = $(shell echo $$(($(ROOTFS_PARTITION_SIZE) / 1024)))
EXTRAS_SIZE_KB  = $(shell echo $$(($(FLASH_SIZE_KB) - $(ROOTFS_OFFSET) / 1024 - $(ROOTFS_SIZE_KB))))

FIRMWARE_NOBOOT_SIZE = $(shell echo $$(($(FLASH_SIZE) - $(U_BOOT_PARTITION_SIZE) - $(UB_ENV_PARTITION_SIZE) - $(CONFIG_PARTITION_SIZE))))

UPGRADE_SIZE_KB = $(shell echo $$(($(FLASH_SIZE_KB) - $(U_BOOT_SIZE_KB) - $(UB_ENV_SIZE_KB) - $(CONFIG_SIZE_KB))))

# dynamic partitions
EXTRAS_PARTITION_SIZE = $(shell echo $$(($(FLASH_SIZE) - $(EXTRAS_OFFSET))))
EXTRAS_LLIMIT := $(shell echo $$(($(ALIGN_BLOCK) * 5)))
else
FLASH_SIZE_KB :=
FLASH_SIZE :=
FLASH_SIZE_HEX :=
U_BOOT_PARTITION_SIZE :=
UB_ENV_PARTITION_SIZE :=
CONFIG_PARTITION_SIZE :=
EXTRAS_LLIMIT :=
endif

# partition offsets
ifeq ($(SKIP_CAMERA_SELECTION),)
U_BOOT_OFFSET := 0
UB_ENV_OFFSET = $(shell echo $$(($(U_BOOT_OFFSET) + $(U_BOOT_PARTITION_SIZE))))
CONFIG_OFFSET = $(shell echo $$(($(UB_ENV_OFFSET) + $(UB_ENV_PARTITION_SIZE))))
KERNEL_OFFSET = $(shell echo $$(($(CONFIG_OFFSET) + $(CONFIG_PARTITION_SIZE))))
ROOTFS_OFFSET = $(shell echo $$(($(KERNEL_OFFSET) + $(KERNEL_PARTITION_SIZE))))
EXTRAS_OFFSET = $(shell echo $$(($(ROOTFS_OFFSET) + $(ROOTFS_PARTITION_SIZE))))

# special case with no uboot nor env
EXTRAS_OFFSET_NOBOOT = $(shell echo $$(($(KERNEL_PARTITION_SIZE) + $(ROOTFS_PARTITION_SIZE))))

export CONFIG_OFFSET
else
U_BOOT_OFFSET :=
UB_ENV_OFFSET :=
CONFIG_OFFSET :=
KERNEL_OFFSET :=
ROOTFS_OFFSET :=
EXTRAS_OFFSET :=
EXTRAS_OFFSET_NOBOOT :=
endif
export FLASH_SIZE_MB

# make command for buildroot
BR2_MAKE = $(MAKE) -C $(BR2_EXTERNAL)/buildroot \
	BR2_EXTERNAL=$(BR2_EXTERNAL) \
	O=$(OUTPUT_DIR) \
	BR2_DL_DIR=$(BR2_DL_DIR)

.PHONY: all bootstrap build build_fast clean clean-nfs-debug cleanbuild defconfig distclean \
	dev fast help pack remove_bins repack sdk toolchain update upboot-ota \
	upload_tftp upload_serial upgrade_ota br-% check-config force-config show-config-deps clean-config \
	tftpd-start tftpd-stop tftpd-restart tftpd-status tftpd-logs show-vars run

# Run a binary under QEMU in the build sysroot.
# Usage: CAMERA=<camera> make run CMD="/bin/ffmpeg --help"  (binary with args)
#        CAMERA=<camera> make run /bin/ffmpeg               (binary only, no args)
CMD ?=
ifeq (run,$(firstword $(MAKECMDGOALS)))
  ifneq ($(CMD),)
    _RUN_CMD := $(CMD)
  else
    _RUN_CMD := $(wordlist 2,$(words $(MAKECMDGOALS)),$(MAKECMDGOALS))
    ifneq ($(_RUN_CMD),)
      $(eval $(_RUN_CMD):;@:)
    endif
  endif
endif

# Default: fast parallel incremental build
all: defconfig build_fast pack
	@$(TEAL) "$@"

# legacy target used by GitHub CI
fast: defconfig build_fast pack
	@$(TEAL) "$@"

# Development build: slow serial for debugging compilation issues
dev: defconfig build pack
	@$(TEAL) "$@"

# Clean build from scratch with parallel compilation
cleanbuild: distclean defconfig build_fast pack
	@$(TEAL) "$@"
ifneq ($(TFTP_IP_ADDRESS),)
	@echo "Copying images to TFTP root..."
	@sudo mkdir -p $(TFTP_ROOT)
	@sudo cp -f $(FIRMWARE_BIN_FULL) $(TFTP_ROOT)/$(FIRMWARE_NAME_FULL)
	@sudo cp -f $(FIRMWARE_BIN_NOBOOT) $(TFTP_ROOT)/$(FIRMWARE_NAME_NOBOOT)
	@sudo cp -f $(FIRMWARE_BIN_FULL).sha256sum $(TFTP_ROOT)/$(FIRMWARE_NAME_FULL).sha256sum 2>/dev/null || true
	@sudo cp -f $(FIRMWARE_BIN_NOBOOT).sha256sum $(TFTP_ROOT)/$(FIRMWARE_NAME_NOBOOT).sha256sum 2>/dev/null || true
	@echo "TFTP: $(TFTP_ROOT)/$(FIRMWARE_NAME_FULL)"
	@echo "TFTP: $(TFTP_ROOT)/$(FIRMWARE_NAME_NOBOOT)"
endif
	@date +%T

# update repo and submodules with buildroot patch management
update:
	@$(TEAL) "$@"
	@echo "=== UPDATING MAIN REPOSITORY ==="
	git pull --rebase --autostash
	@echo "=== UPDATING SUBMODULES ==="
	git submodule init
	git submodule update
	@$(ORANGE) "$(GIT_BRANCH)"

update_manual:
	@echo "=== UPDATING BUILDROOT MANUALS ==="
	@curl -s -z docs/buildroot/manual.pdf -o docs/buildroot/manual.pdf https://buildroot.org/manual.pdf
	@curl -s -z docs/buildroot/manual.txt -o docs/buildroot/manual.txt https://buildroot.org/manual.text

# install what's needed
bootstrap:
	@$(TEAL) "$@"
	$(SCRIPTS_DIR)/dep_check.sh

build: BR2_MAKE_JOBS =
build: $(U_BOOT_ENV_TXT)
	@$(TEAL) "$@"

build_fast: BR2_MAKE_JOBS = -j$(shell nproc)
build_fast: $(U_BOOT_ENV_TXT)
	@$(TEAL) "$@"

### Configuration

FRAGMENTS = $(if $(CAMERA_CONFIG_REAL),$(shell awk '/FRAG:/ {$$1=$$1;gsub(/^.+:\s*/,"");print}' $(CAMERA_CONFIG_REAL)))
RAW_DEFCONFIG_MODE = $(if $(strip $(FRAGMENTS)),,y)

# Configuration dependency files
CONFIG_DEPS_FILE = $(OUTPUT_DIR)/.config.deps
CONFIG_FRAGMENT_FILES = $(addprefix configs/fragments/,$(addsuffix .fragment,$(FRAGMENTS)))
CONFIG_INPUT_FILES = $(TOOLCHAIN_FRAGMENT_FILE) $(CONFIG_FRAGMENT_FILES) $(CAMERA_CONFIG_REAL)
CONFIG_INPUT_FILES += $(THINGINO_USER_FRAGMENT_FILES)
ifneq ($(wildcard $(BR2_EXTERNAL)/local.mk),)
CONFIG_INPUT_FILES += $(BR2_EXTERNAL)/local.mk
endif
CONFIG_INPUT_FILES += $(THINGINO_USER_MK_FILES)

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
	@$(TEAL) "$@"
	@if [ "$(call config_needs_regen)" = "yes" ]; then \
		echo "Configuration files have changed, regenerating .config"; \
		$(MAKE) force-config; \
	else \
		echo "Configuration is up to date"; \
	fi

# Force configuration regeneration
force-config: buildroot/Makefile $(OUTPUT_DIR)/.keep $(CONFIG_PARTITION_DIR)/.keep
	@$(TEAL) "$@"
	# delete older config
	$(info * remove existing .config file)
	rm -rvf $(OUTPUT_DIR)/.config
ifeq ($(RAW_DEFCONFIG_MODE),y)
	# preprocess a plain Buildroot defconfig used by GitHub workflows
	$(info * preprocess raw defconfig $(CAMERA_CONFIG_REAL))
	sed 's/\$$[(]BR2_HOSTARCH[)]/$(BR2_HOSTARCH)/g; s/\$$[(]SOC_ARCH[)]/$(SOC_ARCH)/g; s/\$$[(]SOC_MODEL[)]/$(SOC_MODEL)/g; s/\$$[(]SOC_FAMILY[)]/$(SOC_FAMILY)/g; s/\$$[(]KERNEL_VERSION[)]/$(KERNEL_VERSION)/g; s/\$$[(]KERNEL_SITE[)]/$(subst /,\/,$(KERNEL_SITE))/g; s/\$$[(]KERNEL_HASH[)]/$(KERNEL_HASH)/g; s/\$$[(]UBOOT_BOARDNAME[)]/$(UBOOT_BOARDNAME)/g; s/\$$[(]UBOOT_REPO[)]/$(subst /,\/,$(UBOOT_REPO))/g; s/\$$[(]UBOOT_REPO_VERSION[)]/$(UBOOT_REPO_VERSION)/g' $(CAMERA_CONFIG_REAL) >$(OUTPUT_DIR)/.config
else
	# add toolchain fragment (from preset selection)
	$(info * add toolchain fragment $(TOOLCHAIN_FRAGMENT_FILE))
	@if [ ! -f "$(TOOLCHAIN_FRAGMENT_FILE)" ]; then \
		echo "ERROR: Missing toolchain fragment $(TOOLCHAIN_FRAGMENT_FILE)"; \
		exit 1; \
	fi
	@echo "# $$(basename "$(TOOLCHAIN_FRAGMENT_FILE)")" >> $(OUTPUT_DIR)/.config
	@sed 's/\$$[(]BR2_HOSTARCH[)]/$(BR2_HOSTARCH)/g; s/\$$[(]SOC_ARCH[)]/$(SOC_ARCH)/g; s/\$$[(]SOC_MODEL[)]/$(SOC_MODEL)/g; s/\$$[(]SOC_FAMILY[)]/$(SOC_FAMILY)/g; s/\$$[(]KERNEL_VERSION[)]/$(KERNEL_VERSION)/g; s/\$$[(]KERNEL_SITE[)]/$(subst /,\/,$(KERNEL_SITE))/g; s/\$$[(]KERNEL_HASH[)]/$(KERNEL_HASH)/g; s/\$$[(]UBOOT_BOARDNAME[)]/$(UBOOT_BOARDNAME)/g; s/\$$[(]UBOOT_REPO[)]/$(subst /,\/,$(UBOOT_REPO))/g; s/\$$[(]UBOOT_REPO_VERSION[)]/$(UBOOT_REPO_VERSION)/g' "$(TOOLCHAIN_FRAGMENT_FILE)" >> $(OUTPUT_DIR)/.config
	@echo >> $(OUTPUT_DIR)/.config
	# add other fragments
	$(info * add fragments FRAGMENTS=$(FRAGMENTS) from $(CAMERA_CONFIG_REAL))
	for i in $(FRAGMENTS); do \
		fragment_path="configs/fragments/$$i.fragment"; \
		if [ ! -f "$$fragment_path" ]; then \
			echo "ERROR: Missing fragment $$fragment_path"; \
			exit 1; \
		fi; \
		echo "** add $$fragment_path"; \
		echo "# $$(basename "$$fragment_path")" >> $(OUTPUT_DIR)/.config; \
		sed 's/\$$[(]BR2_HOSTARCH[)]/$(BR2_HOSTARCH)/g; s/\$$[(]SOC_ARCH[)]/$(SOC_ARCH)/g; s/\$$[(]SOC_MODEL[)]/$(SOC_MODEL)/g; s/\$$[(]SOC_FAMILY[)]/$(SOC_FAMILY)/g; s/\$$[(]KERNEL_VERSION[)]/$(KERNEL_VERSION)/g; s/\$$[(]KERNEL_SITE[)]/$(subst /,\/,$(KERNEL_SITE))/g; s/\$$[(]KERNEL_HASH[)]/$(KERNEL_HASH)/g; s/\$$[(]UBOOT_BOARDNAME[)]/$(UBOOT_BOARDNAME)/g; s/\$$[(]UBOOT_REPO[)]/$(subst /,\/,$(UBOOT_REPO))/g; s/\$$[(]UBOOT_REPO_VERSION[)]/$(UBOOT_REPO_VERSION)/g' "$$fragment_path" >>$(OUTPUT_DIR)/.config; \
		echo >>$(OUTPUT_DIR)/.config; \
	done
	# add kernel-specific headers based on SOC requirements
	# @if [ "$(SOC_FAMILY)" = "t23" ] || [ "$(SOC_FAMILY)" = "t40" ] || [ "$(SOC_FAMILY)" = "t41" ] || [ "$(SOC_FAMILY)" = "a1" ]; then
	@if [ "$(KERNEL_VERSION_4)" = "y" ]; then \
		echo "** add kernel headers: 4.4 (SOC: $(SOC_FAMILY))"; \
		echo "BR2_PACKAGE_HOST_LINUX_HEADERS_CUSTOM_4_4=y" >>$(OUTPUT_DIR)/.config; \
		echo "BR2_TOOLCHAIN_EXTERNAL_HEADERS_4_4=y" >>$(OUTPUT_DIR)/.config; \
	else \
		echo "** add kernel headers: 3.10 (SOC: $(SOC_FAMILY))"; \
		echo "BR2_PACKAGE_HOST_LINUX_HEADERS_CUSTOM_3_10=y" >>$(OUTPUT_DIR)/.config; \
		echo "BR2_TOOLCHAIN_EXTERNAL_HEADERS_3_10=y" >>$(OUTPUT_DIR)/.config; \
	fi; \
	echo >>$(OUTPUT_DIR)/.config
	# add camera configuration
	sed 's/\$$[(]SOC_MODEL[)]/$(SOC_MODEL)/g; s/\$$[(]SOC_FAMILY[)]/$(SOC_FAMILY)/g; s/\$$[(]KERNEL_VERSION[)]/$(KERNEL_VERSION)/g; s/\$$[(]KERNEL_SITE[)]/$(subst /,\/,$(KERNEL_SITE))/g; s/\$$[(]KERNEL_HASH[)]/$(KERNEL_HASH)/g; s/\$$[(]UBOOT_BOARDNAME[)]/$(UBOOT_BOARDNAME)/g; s/\$$[(]UBOOT_REPO[)]/$(subst /,\/,$(UBOOT_REPO))/g; s/\$$[(]UBOOT_REPO_VERSION[)]/$(UBOOT_REPO_VERSION)/g' $(CAMERA_CONFIG_REAL) >>$(OUTPUT_DIR)/.config
	# add SOC-derived values
	@echo "# SOC-derived configuration" >>$(OUTPUT_DIR)/.config
	@echo 'BR2_SOC_FAMILY="$(SOC_FAMILY)"' >>$(OUTPUT_DIR)/.config
	@echo 'BR2_SOC_RAM_MB=$(SOC_RAM_MB)' >>$(OUTPUT_DIR)/.config
	@echo >>$(OUTPUT_DIR)/.config
endif
	for file in $(THINGINO_USER_FRAGMENT_FILES); do \
		if [ -f "$$file" ]; then \
			cat "$$file" >>$(OUTPUT_DIR)/.config; \
			printf '\n' >>$(OUTPUT_DIR)/.config; \
		fi; \
	done; \
	rm -f $(OUTPUT_DIR)/local.mk; \
	for file in $(THINGINO_USER_MK_FILES); do \
		if [ -f "$$file" ]; then \
			cat "$$file" >>$(OUTPUT_DIR)/local.mk; \
			printf '\n' >>$(OUTPUT_DIR)/local.mk; \
		fi; \
	done; \
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
	@$(TEAL) "$@"
	# Ensure buildroot is properly configured
	$(BR2_MAKE) BR2_DEFCONFIG=$(CAMERA_CONFIG_REAL) olddefconfig

# Configuration debugging and maintenance targets
show-config-deps:
	@$(TEAL) "$@"
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
	@$(TEAL) "$@"
	rm -f $(OUTPUT_DIR)/.config $(CONFIG_DEPS_FILE) $(OUTPUT_DIR)/.config_original

# call configurator
menuconfig: check-config $(OUTPUT_DIR)/.config
	@$(TEAL) "$@"
	$(BR2_MAKE) BR2_DEFCONFIG=$(CAMERA_CONFIG_REAL) menuconfig

nconfig: check-config $(OUTPUT_DIR)/.config
	@$(TEAL) "$@"
	$(BR2_MAKE) BR2_DEFCONFIG=$(CAMERA_CONFIG_REAL) nconfig

# permanently save changes to the defconfig
saveconfig:
	@$(TEAL) "$@"
	$(BR2_MAKE) BR2_DEFCONFIG=$(CAMERA_CONFIG_REAL) savedefconfig

### Files

# Clean camera-specific NFS debug artifacts
clean-nfs-debug:
	@$(TEAL) "$@"
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
	@$(TEAL) "$@"
	rm -rf $(OUTPUT_DIR)/target
	rm -rf $(OUTPUT_DIR)/config
	rm -rf $(OUTPUT_DIR)/extras
	rm -f $(FIRMWARE_BIN_FULL) $(FIRMWARE_BIN_FULL).sha256sum
	rm -f $(FIRMWARE_BIN_NOBOOT) $(FIRMWARE_BIN_NOBOOT).sha256sum
	rm -f $(ROOTFS_BIN) $(ROOTFS_TAR) $(EXTRAS_BIN) $(CONFIG_BIN)
#	$(UB_ENV_BIN) $(KERNEL_BIN)

# remove all build files
distclean: clean-nfs-debug
	@$(TEAL) "$@"
	if [ -d "$(OUTPUT_DIR)" ]; then rm -rf $(OUTPUT_DIR); fi

# assemble final images
pack: $(FIRMWARE_BIN_FULL) $(FIRMWARE_BIN_NOBOOT) $(ROOTFS_TAR)
	@$(TEAL) "$@"
	$(info Aligned at: $(ALIGN_BLOCK))
	$(info U-Boot Env: $(shell strings $(UB_ENV_BIN) 2>/dev/null | grep "^mtdparts" || echo "mtdparts not found"))
	$(info Generated:  mtdparts=$(UBOOT_FLASH_CONTROLLER):$(U_BOOT_SIZE_KB)k(boot),$(UB_ENV_SIZE_KB)k(env),$(CONFIG_SIZE_KB)k(config),$(KERNEL_SIZE_KB)k(kernel),$(ROOTFS_SIZE_KB)k(rootfs),$(EXTRAS_SIZE_KB)k@$(shell printf '0x%x' $(EXTRAS_OFFSET))(extras),$(UPGRADE_SIZE_KB)k@$(shell printf '0x%x' $(KERNEL_OFFSET))(upgrade),$(FLASH_SIZE_KB)k@0(all))
	@rm -f $(FIRMWARE_BIN_FULL).sha256sum
	@echo "$(shell echo \# $(CAMERA))" >> $(FIRMWARE_BIN_FULL).sha256sum
	@echo "# ${GIT_BRANCH}+${GIT_HASH}, ${BUILD_DATE}" >> "$(FIRMWARE_BIN_FULL).sha256sum"
	@sha256sum $(FIRMWARE_BIN_FULL) | awk '{print $$1 "  " filename}' filename="$(FIRMWARE_NAME_FULL)" >> $(FIRMWARE_BIN_FULL).sha256sum
	@rm -f $(FIRMWARE_BIN_NOBOOT).sha256sum
	@echo "$(shell echo \# $(CAMERA))" >> $(FIRMWARE_BIN_NOBOOT).sha256sum
	@echo "# ${GIT_BRANCH}+${GIT_HASH}, ${BUILD_DATE}" >> "$(FIRMWARE_BIN_NOBOOT).sha256sum"
	@sha256sum $(FIRMWARE_BIN_NOBOOT) | awk '{print $$1 "  " filename}' filename="$(FIRMWARE_NAME_NOBOOT)" >> $(FIRMWARE_BIN_NOBOOT).sha256sum
	@$(BR2_EXTERNAL)/scripts/save_partition_info.py "$(OUTPUT_DIR)/images/$(CAMERA).md" \
		"$(CAMERA)" $(GIT_BRANCH) $(GIT_HASH) $(BUILD_DATE) "$(UB_ENV_BIN)" \
		$(U_BOOT_OFFSET) $(U_BOOT_PARTITION_SIZE) $(U_BOOT_BIN_SIZE) $(U_BOOT_BIN_SIZE_ALIGNED) \
		$(UB_ENV_OFFSET) $(UB_ENV_PARTITION_SIZE) $(UB_ENV_BIN_SIZE) $(UB_ENV_BIN_SIZE_ALIGNED) \
		$(CONFIG_OFFSET) $(CONFIG_PARTITION_SIZE) $(CONFIG_BIN_SIZE) $(CONFIG_BIN_SIZE_ALIGNED) \
		$(KERNEL_OFFSET) $(KERNEL_PARTITION_SIZE) $(KERNEL_BIN_SIZE) \
		$(ROOTFS_OFFSET) $(ROOTFS_PARTITION_SIZE) $(ROOTFS_BIN_SIZE) \
		$(EXTRAS_OFFSET) $(EXTRAS_PARTITION_SIZE) $(EXTRAS_BIN_SIZE) $(EXTRAS_BIN_SIZE_ALIGNED) \
		$(U_BOOT_SIZE_KB) $(UB_ENV_SIZE_KB) $(CONFIG_SIZE_KB) $(KERNEL_SIZE_KB) $(ROOTFS_SIZE_KB) $(EXTRAS_SIZE_KB) \
		$(UPGRADE_SIZE_KB) $(FLASH_SIZE_KB) $(UBOOT_FLASH_CONTROLLER) && \
		cat $(OUTPUT_DIR)/images/$(CAMERA).md
	@$(ORANGE) "Camera: $(CAMERA)"
	@$(ORANGE) "Device IP: $(CAMERA_IP_ADDRESS)"
	@echo ""
	@if [ $(EXTRAS_PARTITION_SIZE) -lt $(EXTRAS_LLIMIT) ]; then $(RED) "EXTRAS PARTITION IS TOO SMALL"; fi
	@if [ $(FIRMWARE_BIN_FULL_SIZE) -gt $(FLASH_SIZE) ]; then $(RED) "OVERSIZE"; fi
	@echo "Image: $(FIRMWARE_BIN_FULL)"
	@#echo "Update Image: $(FIRMWARE_BIN_NOBOOT)"

# rebuild a package with smart configuration check
rebuild-%: force-config
	@$(TEAL) "$@"
	$(BR2_MAKE) $(subst rebuild-,,$@)-dirclean $(subst rebuild-,,$@)

remove_bins:
	@$(TEAL) "$@"
	rm -f $(U_BOOT_BIN) $(KERNEL_BIN) $(ROOTFS_BIN) $(EXTRAS_BIN)

repack: remove_bins pack
	@$(TEAL) "$@"

# build toolchain fast
sdk: defconfig
	@$(TEAL) "$@"
	$(BR2_MAKE) -j$(shell nproc) sdk

source: defconfig
	@$(TEAL) "$@"
	$(BR2_MAKE) BR2_DEFCONFIG=$(CAMERA_CONFIG_REAL) source

# build toolchain
toolchain: defconfig
	@$(TEAL) "$@"
	$(BR2_MAKE) sdk

# flash new uboot image to the camera
upboot_ota:
	@$(TEAL) "$@"
	@[ -n "$(CAMERA_IP_ADDRESS)" ] || { echo "ERROR: IP is required for $@. Use 'make $@ IP=<camera-ip>'."; exit 1; }
	@fw_path="$(U_BOOT_BIN)"; \
	if [ ! -f "$$fw_path" ]; then fw_path="$(GENERIC_U_BOOT_BIN)"; fi; \
	test -f "$$fw_path" || { echo "ERROR: Neither $(U_BOOT_BIN) nor $(GENERIC_U_BOOT_BIN) was found. Run make first."; exit 1; }; \
	$(SCRIPTS_DIR)/fw_ota.sh "$$fw_path" $(CAMERA_IP_ADDRESS)

# flash compiled update image to the camera
update_ota:
	@$(TEAL) "$@"
	@[ -n "$(CAMERA_IP_ADDRESS)" ] || { echo "ERROR: IP is required for $@. Use 'make $@ IP=<camera-ip>'."; exit 1; }
	@fw_path="$(FIRMWARE_BIN_NOBOOT)"; \
	if [ ! -f "$$fw_path" ]; then fw_path="$(GENERIC_FIRMWARE_BIN_NOBOOT)"; fi; \
	test -f "$$fw_path" || { echo "ERROR: Neither $(FIRMWARE_BIN_NOBOOT) nor $(GENERIC_FIRMWARE_BIN_NOBOOT) was found. Run make first."; exit 1; }; \
	$(SCRIPTS_DIR)/fw_ota.sh "$$fw_path" $(CAMERA_IP_ADDRESS)

# flash compiled full image to the camera
upgrade_ota:
	@$(TEAL) "$@"
	@[ -n "$(CAMERA_IP_ADDRESS)" ] || { echo "ERROR: IP is required for $@. Use 'make $@ IP=<camera-ip>'."; exit 1; }
	@fw_path="$(FIRMWARE_BIN_FULL)"; \
	if [ ! -f "$$fw_path" ]; then fw_path="$(GENERIC_FIRMWARE_BIN_FULL)"; fi; \
	test -f "$$fw_path" || { echo "ERROR: Neither $(FIRMWARE_BIN_FULL) nor $(GENERIC_FIRMWARE_BIN_FULL) was found. Run make first."; exit 1; }; \
	$(SCRIPTS_DIR)/fw_ota.sh "$$fw_path" $(CAMERA_IP_ADDRESS)

# upload firmware to tftp server
upload_tftp:
	@$(TEAL) "$@"
	@test -f $(FIRMWARE_BIN_FULL) || { echo "ERROR: $(FIRMWARE_BIN_FULL) not found. Run make first."; exit 1; }
	busybox tftp -l $(FIRMWARE_BIN_FULL) -r $(FIRMWARE_NAME_FULL) -p $(TFTP_IP_ADDRESS)

# Start standalone TFTP server for serving firmware images
tftpd-start:
	@$(TEAL) "$@"
	@mkdir -p $(TFTP_ROOT)
	@if [ "$(TFTP_PORT)" = "69" ] || [ -z "$(TFTP_PORT)" ]; then \
		echo "Port 69 requires sudo - starting with sudo..."; \
		sudo -E TFTP_ROOT=$(TFTP_ROOT) TFTP_PORT=$(TFTP_PORT) $(SCRIPTS_DIR)/tftpd-server.sh start; \
	else \
		TFTP_ROOT=$(TFTP_ROOT) TFTP_PORT=$(TFTP_PORT) $(SCRIPTS_DIR)/tftpd-server.sh start; \
	fi

# Stop standalone TFTP server
tftpd-stop:
	@$(TEAL) "$@"
	@if [ "$(TFTP_PORT)" = "69" ] || [ -z "$(TFTP_PORT)" ]; then \
		sudo $(SCRIPTS_DIR)/tftpd-server.sh stop; \
	else \
		$(SCRIPTS_DIR)/tftpd-server.sh stop; \
	fi

# Restart standalone TFTP server
tftpd-restart:
	@$(TEAL) "$@"
	@if [ "$(TFTP_PORT)" = "69" ] || [ -z "$(TFTP_PORT)" ]; then \
		sudo $(SCRIPTS_DIR)/tftpd-server.sh restart; \
	else \
		$(SCRIPTS_DIR)/tftpd-server.sh restart; \
	fi

# Show standalone TFTP server status
tftpd-status:
	@$(TEAL) "$@"
	@$(SCRIPTS_DIR)/tftpd-server.sh status

# Show standalone TFTP server logs
tftpd-logs:
	@$(TEAL) "$@"
	@$(SCRIPTS_DIR)/tftpd-server.sh logs

# download buildroot cache bundle from latest github release
download-cache:
	@$(TEAL) "$@"
	BR2_EXTERNAL=$(CURDIR) BR2_DL_DIR=$(BR2_DL_DIR) \
		$(CURDIR)/scripts/dl_buildroot_cache.sh

### Buildroot

# delete all build/{package} and per-package/{package} files
br-%-dirclean:
	@$(TEAL) "$@"
	rm -rf $(OUTPUT_DIR)/per-package/$(subst -dirclean,,$(subst br-,,$@)) \
		$(OUTPUT_DIR)/build/$(subst -dirclean,,$(subst br-,,$@))* \
		$(OUTPUT_DIR)/target
	#  \ sed -i /^$(subst -dirclean,,$(subst br-,,$@))/d $(OUTPUT_DIR)/build/packages-file-list.txt

br-%: check-config
	@$(TEAL) "$@"
	$(BR2_MAKE) $(subst br-,,$@)

# checkout buidroot submodule
buildroot/Makefile:
	@$(TEAL) "$@"
	git submodule init
	git submodule update --remote --recursive

# create output directory
$(OUTPUT_DIR)/.keep:
	@$(TEAL) "$@"
	test -d $(OUTPUT_DIR) || mkdir -p $(OUTPUT_DIR)
	touch $@

# create config partition directory
$(CONFIG_PARTITION_DIR)/.keep:
	@$(TEAL) "$@"
	test -d $(CONFIG_PARTITION_DIR) || mkdir -p $(CONFIG_PARTITION_DIR)
	touch $@

# generate a base Buildroot config when missing
$(OUTPUT_DIR)/.config:
	@$(TEAL) "$@"
	$(MAKE) force-config

$(FIRMWARE_BIN_FULL): $(U_BOOT_BIN) $(UB_ENV_BIN) $(CONFIG_BIN) $(KERNEL_BIN) $(ROOTFS_BIN) $(EXTRAS_BIN)
	@$(TEAL) "$@"
	# create a blank slab
	dd if=/dev/zero bs=8M skip=0 count=1 status=none | tr '\000' '\377' > $@
	# add bootloader partition
	dd if=$(U_BOOT_BIN) bs=$(U_BOOT_BIN_SIZE) seek=$(U_BOOT_OFFSET)B count=1 of=$@ conv=notrunc status=none
	# add config partition
	dd if=$(CONFIG_BIN) bs=$(CONFIG_BIN_SIZE) seek=$(CONFIG_OFFSET)B count=1 of=$@ conv=notrunc status=none
	# add kernel partition
	dd if=$(KERNEL_BIN) bs=$(KERNEL_BIN_SIZE) seek=$(KERNEL_OFFSET)B count=1 of=$@ conv=notrunc status=none
	# add rootfs partition
	dd if=$(ROOTFS_BIN) bs=$(ROOTFS_BIN_SIZE) seek=$(ROOTFS_OFFSET)B count=1 of=$@ conv=notrunc status=none
	# add extras partition
	@if [ $(EXTRAS_BIN_SIZE) -gt 0 ]; then \
	  dd if=$(EXTRAS_BIN) bs=$(EXTRAS_BIN_SIZE) seek=$(EXTRAS_OFFSET)B count=1 of=$@ conv=notrunc status=none; \
	fi

$(FIRMWARE_BIN_NOBOOT): $(FIRMWARE_BIN_FULL)
	@$(TEAL) "$@"
	dd if=$(FIRMWARE_BIN_FULL) of=$@ bs=$(FIRMWARE_NOBOOT_SIZE) count=1 skip=$(KERNEL_OFFSET)B

# create config partition image
$(CONFIG_BIN): $(CONFIG_PARTITION_DIR)/.keep
	@$(TEAL) "$@"
	# remove older image if present
	if [ -f $@ ]; then rm $@; fi
	# rebuild config partition staging from layered user overlays
	rm -rf $(CONFIG_PARTITION_DIR)
	mkdir -p $(CONFIG_PARTITION_DIR)
	for dir in $(THINGINO_USER_OVERLAY_DIRS); do \
		$(RSYNC) --archive "$$dir"/ $(CONFIG_PARTITION_DIR)/; \
	done
	# delete stub files
	find $(CONFIG_PARTITION_DIR)/ -name ".*keep" -o -name ".empty" -delete
	# pack the config partition image
	$(HOST_DIR)/sbin/mkfs.jffs2 --little-endian --squash --output=$@ --root=$(CONFIG_PARTITION_DIR)/ \
		--eraseblock=$(ALIGN_BLOCK) --pad=$(CONFIG_PARTITION_SIZE)

# create extras partition image
$(EXTRAS_BIN): $(ROOTFS_BIN) $(U_BOOT_BIN)
	@$(TEAL) "$@"
	# remove older image if present
	if [ -f $@ ]; then rm $@; fi
	rm -rf $(OUTPUT_DIR)/extras
	mkdir -p $(OUTPUT_DIR)/extras
	# extract /opt/ from target rootfs to a separare directory
	$(RSYNC) --exclude='.gitkeep' $(OUTPUT_DIR)/target/opt/ $(OUTPUT_DIR)/extras/
	# empty /opt/ in the rootfs
	rm -rf $(OUTPUT_DIR)/target/opt/*
	# add layered user extras so narrower scopes override broader ones
	for dir in $(THINGINO_USER_OPT_DIRS); do \
		$(RSYNC) --exclude='.gitkeep' --archive "$$dir"/ $(OUTPUT_DIR)/extras/; \
	done
	# pack the extras partition image if directory has content, otherwise it will be created on first use
	if [ -n "$$(find $(OUTPUT_DIR)/extras/ -type f 2>/dev/null)" ]; then \
		$(HOST_DIR)/sbin/mkfs.jffs2 --little-endian --squash --output=$@ --root=$(OUTPUT_DIR)/extras/ \
			--eraseblock=$(ALIGN_BLOCK) --pad=$(EXTRAS_PARTITION_SIZE); \
	else \
		$(HOST_DIR)/sbin/mkfs.jffs2 --little-endian --squash --output=$@ --root=$(OUTPUT_DIR)/extras/ \
			--eraseblock=$(ALIGN_BLOCK); \
	fi

# rebuild kernel
$(KERNEL_BIN):
	@$(TEAL) "$@"
	$(BR2_MAKE) $(BR2_MAKE_JOBS) linux-rebuild
#	mv -vf $(OUTPUT_DIR)/images/uImage $@

# rebuild rootfs (depends on kernel to ensure proper build order)
# Pre-stamp thingino-uboot so Buildroot skips it during rootfs-squashfs.
# It will be dirclean'd and rebuilt properly in the $(U_BOOT_BIN) rule,
# once partition sizes are known from the rootfs.
$(ROOTFS_BIN): $(KERNEL_BIN)
	@$(TEAL) "$@"
	mkdir -p $(OUTPUT_DIR)/build/thingino-uboot-$(UBOOT_REPO_VERSION)
	mkdir -p $(OUTPUT_DIR)/per-package/thingino-uboot/host
	mkdir -p $(OUTPUT_DIR)/per-package/thingino-uboot/target
	touch $(OUTPUT_DIR)/build/thingino-uboot-$(UBOOT_REPO_VERSION)/.stamp_downloaded \
	      $(OUTPUT_DIR)/build/thingino-uboot-$(UBOOT_REPO_VERSION)/.stamp_extracted \
	      $(OUTPUT_DIR)/build/thingino-uboot-$(UBOOT_REPO_VERSION)/.stamp_patched \
	      $(OUTPUT_DIR)/build/thingino-uboot-$(UBOOT_REPO_VERSION)/.stamp_configured \
	      $(OUTPUT_DIR)/build/thingino-uboot-$(UBOOT_REPO_VERSION)/.stamp_built \
	      $(OUTPUT_DIR)/build/thingino-uboot-$(UBOOT_REPO_VERSION)/.stamp_installed \
	      $(OUTPUT_DIR)/build/thingino-uboot-$(UBOOT_REPO_VERSION)/.stamp_target_installed \
	      $(OUTPUT_DIR)/build/thingino-uboot-$(UBOOT_REPO_VERSION)/.stamp_images_installed
	$(BR2_MAKE) $(BR2_MAKE_JOBS) rootfs-squashfs

$(U_BOOT_ENV_TXT): $(ROOTFS_BIN)
	@$(TEAL) "$@"
	touch $@
	grep -v '^#' $(BR2_EXTERNAL)/configs/common.uenv.txt | awk NF | tee -a $@
	grep -v '^#' $(BR2_EXTERNAL)/$(CAMERA_SUBDIR)/$(CAMERA)/$(CAMERA).uenv.txt | awk NF | tee -a $@
	for file in $(THINGINO_USER_UENV_FILES); do \
		grep -v '^#' "$$file" | awk NF | tee -a $@; \
	done
	sort -u -o $@ $@
	# Remove any existing mtdparts and bootcmd lines (will be regenerated with aligned sizes)
	sed -i '/^mtdparts=/d; /^bootcmd=/d; /^kern_addr=/d; /^kern_size=/d' $@
	# Add kernel address and size
	echo "kern_addr=$$(printf '0x%x' $(KERNEL_OFFSET))" >> $@
	echo "kern_size=$$(printf '0x%x' $(KERNEL_PARTITION_SIZE))" >> $@
	# Add complete mtdparts with aligned partitions and virtual aliases
	echo "mtdparts=$(UBOOT_FLASH_CONTROLLER):$(U_BOOT_SIZE_KB)k(boot),$(UB_ENV_SIZE_KB)k(env),$(CONFIG_SIZE_KB)k(config),$(KERNEL_SIZE_KB)k(kernel),$(ROOTFS_SIZE_KB)k(rootfs),$(EXTRAS_SIZE_KB)k@$$(printf '0x%x' $(EXTRAS_OFFSET))(extras),$(UPGRADE_SIZE_KB)k@$$(printf '0x%x' $(KERNEL_OFFSET))(upgrade),$(FLASH_SIZE_KB)k@0(all)" >> $@
	# Simplified bootcmd - no need for sq probe or run mtdparts
	echo 'bootcmd=sf probe;setenv bootargs mem=$${osmem} rmem=$${rmem}$$(UBOOT_ISPMEM)$$(UBOOT_NMEM)console=$${serialport},$${baudrate}n8 panic=$${panic_timeout} root=$${root} rootfstype=$${rootfstype} init=$${init} mtdparts=$${mtdparts};sf read $${baseaddr} $${kern_addr} $${kern_size};bootm $${baseaddr}' >> $@
	exit

# Rebuild U-Boot with actual partition sizes after rootfs is ready
$(U_BOOT_BIN): $(U_BOOT_ENV_TXT)
	$(info -------------------------------- $@ (rebuilding with actual partition sizes))
	$(BR2_MAKE) $(BR2_MAKE_JOBS) thingino-uboot-dirclean thingino-uboot

$(UB_ENV_BIN): $(U_BOOT_ENV_TXT)
	@$(TEAL) "$@"
	$(HOST_DIR)/bin/mkenvimage -s $(UB_ENV_PARTITION_SIZE) -o $@ $(U_BOOT_ENV_TXT)

# create .tar file of rootfs
$(ROOTFS_TAR):
	@$(TEAL) "$@"
	$(BR2_MAKE) $(BR2_MAKE_JOBS) all

build-all:
	@$(TEAL) "$@"
	@echo "Building all cameras from $(CAMERA_SUBDIR)"
	@log_dir="$(HOME)/output-$(GIT_BRANCH)/build-all-logs-$$(date +%Y%m%d-%H%M%S)"; \
	mkdir -p "$$log_dir"; \
	echo "Logs will be saved to: $$log_dir"; \
	failed_cameras=""; \
	total=0; \
	success=0; \
	failed=0; \
	for camera_dir in $(CAMERA_SUBDIR)/*; do \
		if [ -d "$$camera_dir" ]; then \
			camera=$$(basename $$camera_dir); \
			total=$$((total + 1)); \
			log_file="$$log_dir/$$camera.log"; \
			echo ""; \
			echo "========================================"; \
			echo "Building camera $$total: $$camera"; \
			echo "Log: $$log_file"; \
			echo "========================================"; \
			if env -u OUTPUT_DIR $(MAKE) CAMERA=$$camera distclean defconfig build_fast pack 2>&1 | tee "$$log_file"; then \
				echo "✓ SUCCESS: $$camera" | tee -a "$$log_file"; \
				success=$$((success + 1)); \
			else \
				echo "✗ FAILED: $$camera" | tee -a "$$log_file"; \
				failed=$$((failed + 1)); \
				failed_cameras="$$failed_cameras$$camera\n"; \
			fi; \
		fi; \
	done; \
	echo ""; \
	echo "========================================" | tee "$$log_dir/summary.log"; \
	echo "BUILD SUMMARY" | tee -a "$$log_dir/summary.log"; \
	echo "========================================" | tee -a "$$log_dir/summary.log"; \
	echo "Total cameras: $$total" | tee -a "$$log_dir/summary.log"; \
	echo "Successful: $$success" | tee -a "$$log_dir/summary.log"; \
	echo "Failed: $$failed" | tee -a "$$log_dir/summary.log"; \
	echo "Logs saved to: $$log_dir" | tee -a "$$log_dir/summary.log"; \
	if [ $$failed -gt 0 ]; then \
		echo "" | tee -a "$$log_dir/summary.log"; \
		echo "Failed cameras:" | tee -a "$$log_dir/summary.log"; \
		echo -e "$$failed_cameras" | tee -a "$$log_dir/summary.log"; \
		exit 1; \
	fi

help:
	@$(TEAL) "$@"
	@echo -e "\n\
	Usage:\n\
	  make bootstrap      install system deps\n\
	  make update         update local repo and submodules (excludes buildroot)\n\
	  make                build from scratch (clean + parallel) [DEFAULT]\n\
	  make dev            serial build for debugging compilation errors\n\
	  make fast           fast incremental build (no clean)\n\
	  make cleanbuild     same as 'make' (clean + parallel build)\n\
	  make build          serial build (no clean)\n\
	  make pack           create firmware images\n\
	  make clean          clean before reassembly\n\
	  make distclean      start building from scratch\n\
	  make rebuild-<pkg>  perform a clean package rebuild for <pkg>\n\
	  make show-vars      print key build variables\n\
	  make build-all      build all camera configs one by one\n\
	  make help           print this help\n\
	  make run <bin>      run a target binary via QEMU (e.g. make run bin/ffmpeg)\n\
	  \n\
	Configuration Management:\n\
	  make defconfig      configure buildroot (auto-detects changes)\n\
	  make check-config   check if configuration needs regeneration\n\
	  make force-config   force configuration regeneration\n\
	  make show-config-deps  show configuration dependencies\n\
	  make clean-config   remove configuration files\n\
	  \n\
	Buildroot Submodule Management:\n\
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

# Print key variables commonly needed for tooling
show-vars:
	@$(TEAL) "$@"
	@echo "AVPU_CLK = $(AVPU_CLK)";
	@echo "AVPU_CLK_SRC = $(AVPU_CLK_SRC)";
	@echo "BR2_DL_DIR = $(BR2_DL_DIR)";
	@echo "BR2_EXTERNAL = $(BR2_EXTERNAL)";
	@echo "BR2_LIBC_NAME = $(BR2_LIBC_NAME)";
	@echo "BR2_MAKE = $(BR2_MAKE)";
	@echo "BR2_PACKAGE_THINGINO_UBOOT_BOARDNAME = $(BR2_PACKAGE_THINGINO_UBOOT_BOARDNAME)";
	@echo "BR2_PACKAGE_THINGINO_UBOOT_FORMAT_CUSTOM_NAME = $(BR2_PACKAGE_THINGINO_UBOOT_FORMAT_CUSTOM_NAME)";
	@echo "BR2_TOOLCHAIN_EXTERNAL_URL = $(BR2_TOOLCHAIN_EXTERNAL_URL)";
	@echo "CAMERA = $(CAMERA)";
	@echo "CAMERA_SUBDIR = $(CAMERA_SUBDIR)";
	@echo "FLASH_SIZE = $(FLASH_SIZE)";
	@echo "FLASH_SIZE_KB = $(FLASH_SIZE_KB)";
	@echo "FLASH_SIZE_MB = $(FLASH_SIZE_MB)";
	@echo "HOST_DIR = $(HOST_DIR)";
	@echo "IP = $(IP)";
	@echo "ISP_CH0_PRE_DEQUEUE_INTERRUPT_PROCESS = $(ISP_CH0_PRE_DEQUEUE_INTERRUPT_PROCESS)";
	@echo "ISP_CH0_PRE_DEQUEUE_TIME = $(ISP_CH0_PRE_DEQUEUE_TIME)";
	@echo "ISP_CH0_PRE_DEQUEUE_VALID_LINES = $(ISP_CH0_PRE_DEQUEUE_VALID_LINES)";
	@echo "ISP_CLK = $(ISP_CLK)";
	@echo "ISP_CLKA_CLK = $(ISP_CLKA_CLK)";
	@echo "ISP_CLKA_CLK_SRC = $(ISP_CLKA_CLK_SRC)";
	@echo "ISP_CLK_SRC = $(ISP_CLK_SRC)";
	@echo "ISP_DAY_NIGHT_SWITCH_DROP_FRAME_NUM = $(ISP_DAY_NIGHT_SWITCH_DROP_FRAME_NUM)";
	@echo "ISP_MEMOPT = $(ISP_MEMOPT)";
	@echo "KERNEL_BRANCH = $(KERNEL_BRANCH)";
	@echo "KERNEL_HASH = $(shell git ls-remote $(KERNEL_SITE) $(KERNEL_BRANCH) | head -1 | cut -f1)";
	@echo "KERNEL_SITE = $(KERNEL_SITE)";
	@echo "KERNEL_TARBALL_URL = $(KERNEL_TARBALL_URL)";
	@echo "KERNEL_VERSION = $(KERNEL_VERSION)";
	@echo "OUTPUT_DIR = $(OUTPUT_DIR)";
	@echo "SENSOR_1_MODEL = $(SENSOR_1_MODEL)";
	@echo "SENSOR_2_MODEL = $(SENSOR_2_MODEL)";
	@echo "SENSOR_3_MODEL = $(SENSOR_3_MODEL)";
	@echo "SENSOR_4_MODEL = $(SENSOR_4_MODEL)";
	@echo "SOC_FAMILY = $(SOC_FAMILY)";
	@echo "SOC_FAMILY_CAPS = $(SOC_FAMILY_CAPS)";
	@echo "SOC_MODEL = $(SOC_MODEL)";
	@echo "SOC_MODEL_LESS_Z = $(SOC_MODEL_LESS_Z)";
	@echo "SOC_RAM_MB = $(SOC_RAM_MB)";
	@echo "SOC_VENDOR = $(SOC_VENDOR)";
	@echo "STREAMER = $(STREAMER)";
	@echo "THINGINO_USER_CAMERA_DIR = $(THINGINO_USER_CAMERA_DIR)";
	@echo "THINGINO_USER_COMMON_DIR = $(THINGINO_USER_COMMON_DIR)";
	@echo "THINGINO_USER_DEVICE_DIR = $(THINGINO_USER_DEVICE_DIR)";
	@echo "THINGINO_USER_DIR = $(THINGINO_USER_DIR)";
	@echo "THINGINO_USER_FRAGMENT_FILES = $(THINGINO_USER_FRAGMENT_FILES)";
	@echo "THINGINO_USER_JSON_FILES = $(THINGINO_USER_JSON_FILES)";
	@echo "THINGINO_USER_MOTORS_JSON_FILES = $(THINGINO_USER_MOTORS_JSON_FILES)";
	@echo "THINGINO_USER_MK_FILES = $(THINGINO_USER_MK_FILES)";
	@echo "THINGINO_USER_OPT_DIRS = $(THINGINO_USER_OPT_DIRS)";
	@echo "THINGINO_USER_OVERLAY_DIRS = $(THINGINO_USER_OVERLAY_DIRS)";
	@echo "THINGINO_USER_UENV_FILES = $(THINGINO_USER_UENV_FILES)";
	@echo "UBOOT_BOARDNAME = $(UBOOT_BOARDNAME)";
	@echo "UBOOT_REPO = $(UBOOT_REPO)";
	@echo "UBOOT_REPO_BRANCH = $(UBOOT_REPO_BRANCH)";
	@echo "UBOOT_REPO_VERSION = $(UBOOT_REPO_VERSION)";

run:
	@$(TEAL) "$@"
	$(SCRIPTS_DIR)/qemu_run.sh $(OUTPUT_DIR)/target $(_RUN_CMD)

upload_serial:
	@$(TEAL) "$@"
	@test -f $(FIRMWARE_BIN_FULL) || { echo "ERROR: $(FIRMWARE_BIN_FULL) not found. Run make first."; exit 1; }
	$(HOST_DIR)/bin/thingino-cloner -i 0 -b -w $(FIRMWARE_BIN_FULL) --cpu $(SOC_FAMILY) --firmware-dir $(HOST_DIR)/share/thingino-cloner/firmwares --reboot

# Catch-all rule: forward undefined targets to buildroot
# This allows running buildroot targets directly without the br- prefix
# e.g., "make linux-menuconfig" instead of "make br-linux-menuconfig"
# Note: This must come after all explicit target definitions
# Note: check-config is NOT a prerequisite here because:
#   1. It would break non-buildroot targets (like when this rule incorrectly matched 'update')
#   2. Buildroot targets will fail gracefully if config is missing
#   3. Users should use 'make br-<target>' for buildroot targets, which includes check-config
.DEFAULT: check-config
	@$(TEAL) "$@"
	$(BR2_MAKE) $@
