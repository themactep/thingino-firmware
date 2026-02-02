# Force bash as shell for Make
SHELL := /bin/bash

# Targets that don't require board selection
NOCAMERA_TARGETS := help bootstrap update update-buildroot update-buildroot-patches reset-buildroot download-cache agent-info show-vars tftpd-start tftpd-stop tftpd-restart tftpd-status tftpd-logs

# Check if current target is exempted from board selection
# MAKECMDGOALS contains the targets specified on command line
CURRENT_TARGETS := $(MAKECMDGOALS)
ifeq ($(CURRENT_TARGETS),)
CURRENT_TARGETS := all
endif

# Check if any current target is in the exempted list
SKIP_CAMERA_SELECTION := $(strip $(foreach target,$(CURRENT_TARGETS),$(filter $(target),$(NOCAMERA_TARGETS))))

# Only proceed with board selection if not exempted
ifeq ($(SKIP_CAMERA_SELECTION),)
BUILD_MEMO := /tmp/thingino-board.$(shell ps -o ppid= -p $$PPID | xargs)

# Check if CAMERA was provided via command line (skip all prompts)
ifdef CAMERA
CAMERA_CONFIG := $(shell find $(CAMERA_SUBDIR) -name "$(CAMERA)_defconfig")
else
# Check if CAMERA was provided via command line
ifeq ($(CAMERA),)
# Use select_camera script for interactive selection (it handles memo internally)
CAMERA := $(shell $(SCRIPTS_DIR)/select_camera.sh $(CAMERA_SUBDIR) $(BUILD_MEMO) 2>/dev/tty | sed 's/\x1b[^a-zA-Z]*[a-zA-Z]//g' | tr -d '\n\r')
# Check if selection was cancelled
ifeq ($(CAMERA),)
$(error Camera selection cancelled)
endif
# After selection, find the config file
CAMERA_CONFIG := $(shell find $(CAMERA_SUBDIR)/$(CAMERA) -name "$(CAMERA)_defconfig")
else
# CAMERA was provided via command line, find its config
CAMERA_CONFIG := $(shell find $(CAMERA_SUBDIR) -name "$(CAMERA)_defconfig")
endif
endif

ifeq ($(CAMERA_CONFIG),)
ifeq ($(CAMERA),)
$(error * No camera selected)
else
$(error * Config file not found for camera: $(CAMERA))
endif
else ifneq ($(shell echo "$(CAMERA_CONFIG)" | wc -w), 1)
$(error * found multiple config files: $(CAMERA_CONFIG))
else
$(info CAMERA_CONFIG = $(CAMERA_CONFIG))
endif

# Ensure CAMERA is set from CAMERA_CONFIG if not already set
CAMERA ?= $(shell basename "$(CAMERA_CONFIG)" | sed -E "s/_defconfig//")
CAMERA_CONFIG_REAL := $(shell realpath "$(BR2_EXTERNAL)/$(CAMERA_CONFIG)" 2>/dev/null)
$(info CAMERA_CONFIG_REAL = $(CAMERA_CONFIG_REAL))

# Check if the camera config file actually exists
ifeq ($(CAMERA_CONFIG_REAL),)
$(error * Camera config file not found: $(BR2_EXTERNAL)/$(CAMERA_CONFIG). Please check if the profile still exists or remove the BUILD_MEMO file: $(BUILD_MEMO))
endif

MODULE_CONFIG = $(shell awk '/MODULE:/ {$$1=$$1;gsub(/^.+:\s*/,"");print}' $(CAMERA_CONFIG_REAL))
ifeq ($(MODULE_CONFIG),)
MODULE_CONFIG_REAL = $(CAMERA_CONFIG_REAL)
else
MODULE_CONFIG_REAL = $(shell realpath "$(BR2_EXTERNAL)/configs/modules/$(MODULE_CONFIG)_defconfig")
endif
$(info MODULE_CONFIG = $(MODULE_CONFIG))

#$(info * restore CAMERA for CAMERA_CONFIG)
#CAMERA = $(shell basename "$(CAMERA_CONFIG_REAL)")

export CAMERA
$(info CAMERA = $(CAMERA))

# read camera config file
include $(CAMERA_CONFIG_REAL)

# read module config file
include $(MODULE_CONFIG_REAL)

else
# Board selection skipped for exempted targets
# Set minimal required variables to prevent errors
CAMERA_CONFIG :=
CAMERA_CONFIG_REAL :=
MODULE_CONFIG :=
MODULE_CONFIG_REAL :=
CAMERA :=
$(info Board selection skipped for target: $(CURRENT_TARGETS))
endif
