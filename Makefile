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

# project directories
BR2_EXTERNAL := $(CURDIR)
SCRIPTS_DIR := $(BR2_EXTERNAL)/scripts
BUILDROOT_DIR := $(BR2_EXTERNAL)/buildroot
BUILDROOT_OVERRIDE_PATCH_DIR := $(BR2_EXTERNAL)/package/all-patches/buildroot

# --- CI / automation fast-paths -------------------------------------
#
# WORKFLOW=1
#   Skips the dependency check and interactive camera selection.
#   Intended for CI/CD pipelines where the environment is known-good
#   and CAMERA= is always supplied on the command line.  Without this
#   flag, a headless 'make' without CAMERA= would hang waiting for
#   fzf/whiptail input that will never come.
#
# PRISTINE=1
#   Disables user configuration layer ($(THINGINO_USER_DIR) set to
#   /dev/null).  Use for reproducible/OEM builds where local user
#   fragments, overlays, and local.mk must not leak into the image.
#
# Run dependency check before doing anything.
# Skip when WORKFLOW=1, when .prereqs.done exists, or for `make update`.
ifeq ($(WORKFLOW),)
ifneq ($(filter update,$(MAKECMDGOALS)),)
$(info Skipping dependency check for update target)
else ifeq ($(wildcard $(CURDIR)/.prereqs.done),)
_dep_check := $(shell $(SCRIPTS_DIR)/dep_check.sh>&2; echo $$?)
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
TFTP_ROOT ?=

# Buildroot downloads directory
# can be reused from environment, just export the value:
# export BR2_DL_DIR=/path/to/your/local/storage
BR2_DL_DIR ?= $(BR2_EXTERNAL)/dl

THINGINO_USER_DIR ?= $(BR2_EXTERNAL)/user
ifdef PRISTINE
THINGINO_USER_DIR := /dev/null
endif
export THINGINO_USER_DIR
THINGINO_USER_COMMON_DIR := $(THINGINO_USER_DIR)/common

# Global backup directory for camera overlay archives
THINGINO_BACKUP_DIR ?= $(HOME)/.thingino/backups

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
export CAMERA_CONFIG_REAL

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
THINGINO_USER_PRUDYNT_JSON_FILES := $(wildcard $(THINGINO_USER_COMMON_DIR)/prudynt.json)
THINGINO_USER_UENV_FILES := $(wildcard $(THINGINO_USER_COMMON_DIR)/local.uenv.txt)
THINGINO_USER_OVERLAY_DIRS := $(wildcard $(THINGINO_USER_COMMON_DIR)/overlay)
THINGINO_USER_OPT_DIRS := $(wildcard $(THINGINO_USER_COMMON_DIR)/opt)
THINGINO_ROOT_LOCAL_MK_FILES := $(wildcard $(BR2_EXTERNAL)/local.mk)

ifdef THINGINO_USER_CAMERA_DIR
THINGINO_USER_FRAGMENT_FILES += $(wildcard $(THINGINO_USER_CAMERA_DIR)/local.fragment)
THINGINO_USER_MK_FILES += $(wildcard $(THINGINO_USER_CAMERA_DIR)/local.mk)
THINGINO_USER_JSON_FILES += $(wildcard $(THINGINO_USER_CAMERA_DIR)/thingino.json)
THINGINO_USER_PRUDYNT_JSON_FILES += $(wildcard $(THINGINO_USER_CAMERA_DIR)/prudynt.json)
THINGINO_USER_UENV_FILES += $(wildcard $(THINGINO_USER_CAMERA_DIR)/local.uenv.txt)
THINGINO_USER_OVERLAY_DIRS += $(wildcard $(THINGINO_USER_CAMERA_DIR)/overlay)
THINGINO_USER_OPT_DIRS += $(wildcard $(THINGINO_USER_CAMERA_DIR)/opt)
endif

ifdef THINGINO_USER_DEVICE_DIR
THINGINO_USER_FRAGMENT_FILES += $(wildcard $(THINGINO_USER_DEVICE_DIR)/local.fragment)
THINGINO_USER_MK_FILES += $(wildcard $(THINGINO_USER_DEVICE_DIR)/local.mk)
THINGINO_USER_JSON_FILES += $(wildcard $(THINGINO_USER_DEVICE_DIR)/thingino.json)
THINGINO_USER_PRUDYNT_JSON_FILES += $(wildcard $(THINGINO_USER_DEVICE_DIR)/prudynt.json)
THINGINO_USER_UENV_FILES += $(wildcard $(THINGINO_USER_DEVICE_DIR)/local.uenv.txt)
THINGINO_USER_OVERLAY_DIRS += $(wildcard $(THINGINO_USER_DEVICE_DIR)/overlay)
THINGINO_USER_OPT_DIRS += $(wildcard $(THINGINO_USER_DEVICE_DIR)/opt)
endif

export THINGINO_USER_COMMON_DIR
export THINGINO_USER_CAMERA_DIR
export THINGINO_USER_DEVICE_DIR
export THINGINO_ROOT_LOCAL_MK_FILES
export THINGINO_USER_FRAGMENT_FILES
export THINGINO_USER_MK_FILES
export THINGINO_USER_JSON_FILES
export THINGINO_USER_PRUDYNT_JSON_FILES
export THINGINO_USER_UENV_FILES
export THINGINO_USER_OVERLAY_DIRS
export THINGINO_USER_OPT_DIRS

define collect_user_tree_files
$(strip $(foreach dir,$(1),$(shell if [ -d "$(dir)" ]; then find "$(dir)" -type f | LC_ALL=C sort; fi)))
endef

THINGINO_USER_OVERLAY_FILES := $(call collect_user_tree_files,$(THINGINO_USER_OVERLAY_DIRS))
THINGINO_USER_OPT_FILES := $(call collect_user_tree_files,$(THINGINO_USER_OPT_DIRS))

BUILD_SUMMARY_TARGETS := all fast dev cleanbuild build build_fast
ifeq ($(origin THINGINO_BUILD_START_EPOCH), undefined)
THINGINO_BUILD_START_EPOCH := $(shell date +%s)
endif
export THINGINO_BUILD_START_EPOCH
ifeq ($(origin THINGINO_BUILD_START_DISK_SECTORS), undefined)
THINGINO_BUILD_START_DISK_SECTORS := $(shell $(SCRIPTS_DIR)/disk_sectors_written.sh)
endif
export THINGINO_BUILD_START_DISK_SECTORS
THINGINO_LOG_TARGETS := all fast dev cleanbuild build build_fast pack repack

define print_build_user_files_section
$(if $(strip $(2)),$(info $(1):)$(foreach file,$(2),$(info   - $(file))),$(info $(1): none))
endef

ifneq ($(filter $(BUILD_SUMMARY_TARGETS),$(CURRENT_TARGETS)),)
$(info )
$(info === User Build Inputs ===)
$(info THINGINO_USER_DIR: $(THINGINO_USER_DIR))
$(call print_build_user_files_section,repo local.mk,$(THINGINO_ROOT_LOCAL_MK_FILES))
$(call print_build_user_files_section,local.fragment,$(THINGINO_USER_FRAGMENT_FILES))
$(call print_build_user_files_section,user local.mk,$(THINGINO_USER_MK_FILES))
$(call print_build_user_files_section,thingino.json,$(THINGINO_USER_JSON_FILES))
$(call print_build_user_files_section,prudynt.json,$(THINGINO_USER_PRUDYNT_JSON_FILES))
$(call print_build_user_files_section,local.uenv.txt,$(THINGINO_USER_UENV_FILES))
$(call print_build_user_files_section,overlay files,$(THINGINO_USER_OVERLAY_FILES))
$(call print_build_user_files_section,opt files,$(THINGINO_USER_OPT_FILES))
$(info =========================)
$(info )
endif

FRAGMENTS = $(if $(CAMERA_CONFIG_REAL),$(shell awk '/FRAG:/ {$$1=$$1;gsub(/^.+:\s*/,"");print}' $(CAMERA_CONFIG_REAL)))
RAW_DEFCONFIG_MODE = $(if $(strip $(FRAGMENTS)),,y)
CONFIG_FRAGMENT_FILES = $(addprefix configs/fragments/,$(addsuffix .fragment,$(FRAGMENTS)))
EARLY_TOOLCHAIN_INPUT_FILES = $(CONFIG_FRAGMENT_FILES) $(CAMERA_CONFIG_REAL) $(THINGINO_USER_FRAGMENT_FILES)

# Resolve toolchain fragment from the effective pre-Buildroot config stack.
TOOLCHAIN_TYPE_RAW := $(if $(CAMERA_CONFIG_REAL),$(strip $(shell $(SCRIPTS_DIR)/resolve_toolchain_value.sh TYPE $(EARLY_TOOLCHAIN_INPUT_FILES))))
TOOLCHAIN_GCC_RAW := $(if $(CAMERA_CONFIG_REAL),$(strip $(shell $(SCRIPTS_DIR)/resolve_toolchain_value.sh GCC $(EARLY_TOOLCHAIN_INPUT_FILES))))
TOOLCHAIN_LIBC_RAW := $(if $(CAMERA_CONFIG_REAL),$(strip $(shell $(SCRIPTS_DIR)/resolve_toolchain_value.sh LIBC $(EARLY_TOOLCHAIN_INPUT_FILES))))

TOOLCHAIN_TYPE_RAW := $(if $(TOOLCHAIN_TYPE_RAW),$(TOOLCHAIN_TYPE_RAW),EXTERNAL)
TOOLCHAIN_GCC_RAW := $(if $(TOOLCHAIN_GCC_RAW),$(TOOLCHAIN_GCC_RAW),16)
TOOLCHAIN_LIBC_RAW := $(if $(TOOLCHAIN_LIBC_RAW),$(TOOLCHAIN_LIBC_RAW),UCLIBC)

TOOLCHAIN_TYPE_TAG := $(if $(filter BUILDROOT,$(TOOLCHAIN_TYPE_RAW)),br,$(if $(filter EXTERNAL,$(TOOLCHAIN_TYPE_RAW)),ext,$(if $(filter LOCAL,$(TOOLCHAIN_TYPE_RAW)),loc,ext)))
TOOLCHAIN_LIBC_TAG := $(shell echo "$(TOOLCHAIN_LIBC_RAW)" | tr 'A-Z' 'a-z')
TOOLCHAIN_FRAGMENT_FILE := configs/fragments/toolchain/$(TOOLCHAIN_TYPE_TAG)-gcc$(TOOLCHAIN_GCC_RAW)-$(TOOLCHAIN_LIBC_TAG).fragment

# Resolve U-Boot version fragment
THINGINO_UBOOT_VERSION_RAW := $(if $(CAMERA_CONFIG_REAL),$(strip $(shell grep -h '^BR2_THINGINO_UBOOT_VERSION_' $(EARLY_TOOLCHAIN_INPUT_FILES) 2>/dev/null | grep '=y$$' | head -1 | sed 's/.*UBOOT_VERSION_\(.*\)=y/\1/')))
THINGINO_UBOOT_VERSION_RAW := $(if $(THINGINO_UBOOT_VERSION_RAW),$(THINGINO_UBOOT_VERSION_RAW),2026_07)
THINGINO_UBOOT_VERSION_TAG := $(if $(filter 2026_07,$(THINGINO_UBOOT_VERSION_RAW)),2026-07,$(if $(filter 2026_04,$(THINGINO_UBOOT_VERSION_RAW)),2026-04,$(if $(filter 2013_07,$(THINGINO_UBOOT_VERSION_RAW)),2013-07,$(if $(filter CUSTOM_FORK,$(THINGINO_UBOOT_VERSION_RAW)),custom-fork,$(shell echo "$(THINGINO_UBOOT_VERSION_RAW)" | tr 'A-Z' 'a-z' | tr '_' '-')))))
THINGINO_UBOOT_FRAGMENT_FILE := configs/fragments/uboot/v$(THINGINO_UBOOT_VERSION_TAG).fragment

UBOOT_BIN_NAME := $(if $(filter 2013-07,$(THINGINO_UBOOT_VERSION_TAG)),u-boot-lzo-with-spl.bin,u-boot-with-spl-lzma.bin)
# loaduenv must run AFTER autoupdate: a full autoupdate erases the whole chip
# (env partition included) and resets, so an env imported before flashing would
# be lost. Running after means uenv.txt is applied on the first boot of the
# freshly flashed firmware (autoupdate skips via its .done marker by then).
AUTOUPDATE_PREFIX := $(if $(filter 2013-07,$(THINGINO_UBOOT_VERSION_TAG)),,run autoupdate;run loaduenv;)

ifneq ($(CAMERA_CONFIG_REAL),)
ifndef TOOLCHAIN_LIBC
TOOLCHAIN_LIBC := $(if $(TOOLCHAIN_LIBC_TAG),$(TOOLCHAIN_LIBC_TAG),musl)
endif
export TOOLCHAIN_LIBC
$(info TOOLCHAIN_LIBC: $(TOOLCHAIN_LIBC))
endif

# working directory - set after CAMERA is defined
# THINGINO_-prefixed variants allow safe overrides from the global environment
ifdef THINGINO_OUTPUT_ROOT_DIR
OUTPUT_ROOT_DIR := $(THINGINO_OUTPUT_ROOT_DIR)
endif
ifdef THINGINO_OUTPUT_DIR
OUTPUT_DIR := $(THINGINO_OUTPUT_DIR)
endif
OUTPUT_ROOT_DIR ?= $(BR2_EXTERNAL)/output
OUTPUT_BASE_DIR = $(OUTPUT_ROOT_DIR)/$(GIT_BRANCH)/$(CAMERA)-$(KERNEL_VERSION)-$(TOOLCHAIN_LIBC)
ifeq ($(SKIP_CAMERA_SELECTION),)
OUTPUT_DIR ?= $(OUTPUT_BASE_DIR)$(if $(IP_OUTPUT_TAG),-$(IP_OUTPUT_TAG))
else
OUTPUT_DIR ?= $(OUTPUT_ROOT_DIR)/$(GIT_BRANCH)
endif
export OUTPUT_DIR

ifneq ($(filter $(THINGINO_LOG_TARGETS),$(CURRENT_TARGETS)),)
THINGINO_LOG_BASENAME := $(shell printf '%s' "$(CURRENT_TARGETS)" | tr ' /' '__' | tr -cd 'A-Za-z0-9._-')
THINGINO_LOG_DIR = $(OUTPUT_DIR)/logs
THINGINO_LOG_TIMESTAMP := $(shell date '+%Y%m%d-%H%M%S')
THINGINO_LOG_FILE ?= $(THINGINO_LOG_DIR)/$(THINGINO_LOG_BASENAME)-$(THINGINO_LOG_TIMESTAMP).log
export THINGINO_LOG_FILE
endif

GENERIC_OUTPUT_DIR = $(OUTPUT_BASE_DIR)

HOST_DIR = $(OUTPUT_DIR)/host

# include thingino makefile only when board configuration is available
ifeq ($(SKIP_CAMERA_SELECTION),)
include $(BR2_EXTERNAL)/thingino.mk
endif

# Capped XBurst1 SoCs (T10/T20/T21/T30) boot a TPL chain with modern u-boot; allow legacy names
ifneq ($(THINGINO_UBOOT_VERSION_TAG),2013-07)
ifneq ($(SOC_MODEL),)
UBOOT_BIN_NAME := $(or $(SOC_UBOOT_BIN),u-boot-with-spl-lzma.bin)
endif
endif

TOOLCHAIN_SOC_TAG := $(SOC_ARCH)
ifeq ($(SOC_ARCH),xburst1)
ifeq ($(KERNEL_VERSION_4),y)
TOOLCHAIN_SOC_TAG := xburst1_4_4
endif
endif
export TOOLCHAIN_SOC_TAG

$(info OUTPUT_DIR: $(OUTPUT_DIR))

# hardcoded variables
WGET := wget --quiet --no-verbose --retry-connrefused --continue --timeout=5
RSYNC := rsync --verbose --archive
NPROC := $(shell nproc)

# Reusable sed expression to substitute template variables in config fragments
SED_CONFIG_VARS = sed \
	's/\$$[(]BR2_HOSTARCH[)]/$(BR2_HOSTARCH)/g; \
	 s/\$$[(]SOC_ARCH[)]/$(SOC_ARCH)/g; \
	 s/\$$[(]SOC_TARGET_ARCH[)]/$(SOC_TARGET_ARCH)/g; \
	 s/\$$[(]TOOLCHAIN_SOC_TAG[)]/$(TOOLCHAIN_SOC_TAG)/g; \
	 s/\$$[(]SOC_MODEL[)]/$(SOC_MODEL)/g; \
	 s/\$$[(]SOC_FAMILY[)]/$(SOC_FAMILY)/g; \
	 s/\$$[(]NAND_FLASH_CONTROLLER_SYM[)]/$(NAND_FLASH_CONTROLLER_SYM)/g; \
	 s/\$$[(]KERNEL_VERSION[)]/$(KERNEL_VERSION)/g; \
	 s/\$$[(]KERNEL_SITE[)]/$(subst /,\/,$(KERNEL_SITE))/g; \
	 s/\$$[(]KERNEL_BRANCH[)]/$(KERNEL_BRANCH)/g; \
	 s/\$$[(]KERNEL_HASH[)]/$(KERNEL_HASH)/g; \
	 s/\$$[(]UBOOT_BOARDNAME[)]/$(UBOOT_BOARDNAME)/g; \
	 s/\$$[(]UBOOT_DEFCONFIG[)]/$(UBOOT_DEFCONFIG)/g; \
	 s/\$$[(]UBOOT_CONFIG_FRAGMENT_FILES[)]/$(subst /,\/,$(UBOOT_CONFIG_FRAGMENT_FILES))/g; \
	 s/\$$[(]U_BOOT_ENV_TXT[)]/$(subst /,\/,$(U_BOOT_ENV_TXT))/g'

ORANGE := printf '\033[1;38;5;214m%s\033[0m\n'
TEAL := printf '\033[1;38;5;30m%s\033[0m\n'
RED := printf '\033[1;38;5;160m%s\033[0m\n'
GREEN := printf '\033[1;38;5;40m%s\033[0m\n'

ALIGN_BLOCK := 65536

U_BOOT_GITHUB_URL := https://github.com/gtxaspec/u-boot-ingenic/releases/download/latest

U_BOOT_BIN = $(OUTPUT_DIR)/images/$(UBOOT_BIN_NAME)
GENERIC_U_BOOT_BIN = $(GENERIC_OUTPUT_DIR)/images/$(UBOOT_BIN_NAME)
U_BOOT_VERSION = $(patsubst "%",%,$(BR2_TARGET_UBOOT_VERSION))
U_BOOT_BUILD_DIR = $(OUTPUT_DIR)/build/uboot-$(U_BOOT_VERSION)

U_BOOT_ENV_TXT = $(OUTPUT_DIR)/uenv.txt
export U_BOOT_ENV_TXT

ifeq ($(SKIP_CAMERA_SELECTION),)
FLASH_SIZE_KB  := $(shell echo $$(($(FLASH_SIZE_MB) * 1024)))
FLASH_SIZE     := $(shell echo $$((($(FLASH_SIZE_KB) * 1024))))
FLASH_SIZE_HEX := $(shell printf '0x%x' $(FLASH_SIZE))

# fixed size partitions
U_BOOT_SIZE_KB := 320
UB_ENV_SIZE_KB := 64
BACKUP_SIZE_KB := 64

# rootfs MTD index -- must match the number of partitions before rootfs
# in the offset chain below (U_BOOT -> UB_ENV -> BACKUP -> KERNEL -> ROOTFS)
ROOTFS_MTD_NUM := 4

UB_ENV_BIN := $(OUTPUT_DIR)/images/u-boot-env.bin
KERNEL_BIN := $(OUTPUT_DIR)/images/uImage
ROOTFS_BIN := $(OUTPUT_DIR)/images/rootfs.squashfs
DATA_BIN := $(OUTPUT_DIR)/images/data.jffs2

FIRMWARE_NAME_FULL = thingino-$(CAMERA).bin

FIRMWARE_BIN_FULL := $(OUTPUT_DIR)/images/$(FIRMWARE_NAME_FULL)
GENERIC_FIRMWARE_BIN_FULL := $(GENERIC_OUTPUT_DIR)/images/$(FIRMWARE_NAME_FULL)

# file sizes
U_BOOT_BIN_SIZE = $(shell stat -c%s $(U_BOOT_BIN))
UB_ENV_BIN_SIZE = $(shell stat -c%s $(UB_ENV_BIN))
KERNEL_BIN_SIZE = $(shell stat -c%s $(KERNEL_BIN))
ROOTFS_BIN_SIZE = $(shell stat -c%s $(ROOTFS_BIN))
DATA_BIN_SIZE = $(shell stat -c%s $(DATA_BIN))

FIRMWARE_BIN_FULL_SIZE = $(shell stat -c%s $(FIRMWARE_BIN_FULL))

U_BOOT_BIN_SIZE_ALIGNED = $(shell echo $$((($(U_BOOT_BIN_SIZE) + $(ALIGN_BLOCK) - 1) / $(ALIGN_BLOCK) * $(ALIGN_BLOCK))))
UB_ENV_BIN_SIZE_ALIGNED = $(shell echo $$((($(UB_ENV_BIN_SIZE) + $(ALIGN_BLOCK) - 1) / $(ALIGN_BLOCK) * $(ALIGN_BLOCK))))
KERNEL_BIN_SIZE_ALIGNED = $(shell echo $$((($(KERNEL_BIN_SIZE) + $(ALIGN_BLOCK) - 1) / $(ALIGN_BLOCK) * $(ALIGN_BLOCK))))
ROOTFS_BIN_SIZE_ALIGNED = $(shell echo $$((($(ROOTFS_BIN_SIZE) + $(ALIGN_BLOCK) - 1) / $(ALIGN_BLOCK) * $(ALIGN_BLOCK))))
DATA_BIN_SIZE_ALIGNED = $(shell echo $$((($(DATA_BIN_SIZE) + $(ALIGN_BLOCK) - 1) / $(ALIGN_BLOCK) * $(ALIGN_BLOCK))))

# fixed size partitions
U_BOOT_PARTITION_SIZE := $(shell echo $$(($(U_BOOT_SIZE_KB) * 1024)))
UB_ENV_PARTITION_SIZE := $(shell echo $$(($(UB_ENV_SIZE_KB) * 1024)))
BACKUP_PARTITION_SIZE := $(shell echo $$(($(BACKUP_SIZE_KB) * 1024)))
KERNEL_PARTITION_SIZE := 1638400  # 1600KB universal (aligned max kernel: 1581008B)
ROOTFS_PARTITION_SIZE = $(ROOTFS_BIN_SIZE_ALIGNED)

export U_BOOT_PARTITION_SIZE
export UB_ENV_PARTITION_SIZE
export BACKUP_PARTITION_SIZE
export KERNEL_PARTITION_SIZE
export ALIGN_BLOCK

# Partition sizes in KB for mtdparts
KERNEL_SIZE_KB  = $(shell echo $$(($(KERNEL_PARTITION_SIZE) / 1024)))
ROOTFS_SIZE_KB  = $(shell echo $$(($(ROOTFS_PARTITION_SIZE) / 1024)))
DATA_SIZE_KB  = $(shell echo $$(($(FLASH_SIZE_KB) - $(ROOTFS_OFFSET) / 1024 - $(ROOTFS_SIZE_KB))))

# dynamic partitions
DATA_PARTITION_SIZE = $(shell echo $$(($(FLASH_SIZE) - $(DATA_OFFSET))))
else
FLASH_SIZE_KB :=
FLASH_SIZE :=
FLASH_SIZE_HEX :=
U_BOOT_PARTITION_SIZE :=
UB_ENV_PARTITION_SIZE :=
BACKUP_PARTITION_SIZE :=
endif

# partition offsets
ifeq ($(SKIP_CAMERA_SELECTION),)
U_BOOT_OFFSET := 0
UB_ENV_OFFSET = $(shell echo $$(($(U_BOOT_OFFSET) + $(U_BOOT_PARTITION_SIZE))))
BACKUP_OFFSET = $(shell echo $$(($(UB_ENV_OFFSET) + $(UB_ENV_PARTITION_SIZE))))
KERNEL_OFFSET = $(shell echo $$(($(BACKUP_OFFSET) + $(BACKUP_PARTITION_SIZE))))
ROOTFS_OFFSET = $(shell echo $$(($(KERNEL_OFFSET) + $(KERNEL_PARTITION_SIZE))))
DATA_OFFSET = $(shell echo $$(($(ROOTFS_OFFSET) + $(ROOTFS_PARTITION_SIZE))))
else
U_BOOT_OFFSET :=
UB_ENV_OFFSET :=
BACKUP_OFFSET :=
KERNEL_OFFSET :=
ROOTFS_OFFSET :=
DATA_OFFSET :=
endif
export FLASH_SIZE_MB
export U_BOOT_SIZE_KB
export UB_ENV_SIZE_KB
export BACKUP_SIZE_KB
export KERNEL_SIZE_KB

# make command for buildroot
BR2_MAKE = $(MAKE) -C $(BR2_EXTERNAL)/buildroot \
	BR2_EXTERNAL=$(BR2_EXTERNAL) \
	O=$(OUTPUT_DIR) \
	BR2_DL_DIR=$(BR2_DL_DIR)

define thingino_run_build
	@if [ -n "$(THINGINO_LOG_FILE)" ]; then \
		mkdir -p "$(THINGINO_LOG_DIR)"; \
		if [ ! -f "$(THINGINO_LOG_FILE)" ]; then \
			echo "Build log: $(THINGINO_LOG_FILE)"; \
		fi; \
		set -o pipefail; $(1) 2>&1 | tee -a "$(THINGINO_LOG_FILE)"; \
	else \
		$(1); \
	fi
endef

.PHONY: all bootstrap build build_fast build-info clean clean-nfs-debug cleanbuild \
	defconfig dev distclean fast help pack ram-build ram-dev ram-setup repack remove_bins \
	sdk toolchain update br-% \
	check-config force-config show-config-deps clean-config \
	tftpd-start tftpd-stop tftpd-restart tftpd-status tftpd-logs tftp-copy tftp-upload \
	backup-overlay user-dirs user-push \
	dfu scriba ota run setup-hooks show-vars

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

# Create user directory skeleton for common, per-camera, and per-device levels
USER_DIR_FILES := local.fragment local.mk local.uenv.txt thingino.json

define create_user_dir
	@mkdir -p $(1)/overlay $(1)/opt
	@$(foreach f,$(USER_DIR_FILES),test -f $(1)/$(f) || touch $(1)/$(f);)
endef


# --- Target fragments --------------------------------------------------

include $(BR2_EXTERNAL)/Makefile.targets
include $(BR2_EXTERNAL)/Makefile.ota
include $(BR2_EXTERNAL)/Makefile.utils
