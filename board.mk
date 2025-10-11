# Targets that don't require board selection
NOBOARD_TARGETS := help bootstrap update update-buildroot update-buildroot-patches reset-buildroot download-cache

# Check if current target is exempted from board selection
# MAKECMDGOALS contains the targets specified on command line
CURRENT_TARGETS := $(MAKECMDGOALS)
ifeq ($(CURRENT_TARGETS),)
CURRENT_TARGETS := all
endif

# Check if any current target is in the exempted list
SKIP_BOARD_SELECTION := $(strip $(foreach target,$(CURRENT_TARGETS),$(filter $(target),$(NOBOARD_TARGETS))))

# Only proceed with board selection if not exempted
ifeq ($(SKIP_BOARD_SELECTION),)

LIST_OF_CAMERAS := $(shell find $(CAMERA_SUBDIR) -type f -name '*_defconfig' | \
	sed -E "s/^(.+)\/(.*)_defconfig/'\0' '\2'/" | sort)

BUILD_MEMO := /tmp/thingino-board.$(shell ps -o ppid $$PPID | tail -1 | xargs)

# Check if CAMERA was provided via command line (skip all prompts)
ifdef CAMERA
  BOARD := $(CAMERA)
  CAMERA_CONFIG = $(shell find $(CAMERA_SUBDIR) -name "$(BOARD)_defconfig")
else
  # Check if BOARD was provided via command line
  ifeq ($(BOARD),)
    # No board specified, check for recent board in memo file
    ifeq ($(shell test -f $(BUILD_MEMO); echo $$?), 0)
      CAMERA_CONFIG = $(shell cat $(BUILD_MEMO))
      ifneq ($(CAMERA_CONFIG),)
        BOARD ?= $(shell basename "$(CAMERA_CONFIG)" | sed -E "s/_defconfig//")
        ifeq ($(shell whiptail --yesno "Use $(BOARD)?" 20 76 3>&1 1>&2 2>&3; echo $$?),1)
          # User declined, clear config and set flag to show menu
          CAMERA_CONFIG =
          BOARD =
          $(shell rm $(BUILD_MEMO))
          SHOW_BOARD_MENU := 1
        endif
      else
        # Memo file exists but is empty, show menu
        SHOW_BOARD_MENU := 1
      endif
    else
      # No memo file, show menu
      SHOW_BOARD_MENU := 1
    endif
  else
    # BOARD was provided via command line, find its config
    CAMERA_CONFIG = $(shell find $(CAMERA_SUBDIR) -name "$(BOARD)_defconfig")
  endif
endif

# Only show board selection menu if explicitly needed
ifeq ($(SHOW_BOARD_MENU),1)
  ifeq ($(CAMERA_CONFIG),)
    CAMERA_CONFIG := $(or $(shell whiptail --title "Config files" \
	  --menu "Select a camera config:" 20 76 12 \
	  --notags $(LIST_OF_CAMERAS) 3>&1 1>&2 2>&3))
    # After menu selection, derive BOARD from the selected config
    ifneq ($(CAMERA_CONFIG),)
      BOARD := $(shell basename "$(CAMERA_CONFIG)" | sed -E "s/_defconfig//")
    endif
  endif
endif

ifeq ($(CAMERA_CONFIG),)
  $(error * config file not found)
else ifneq ($(shell echo "$(CAMERA_CONFIG)" | wc -w), 1)
  $(error * found multiple config files: $(CAMERA_CONFIG))
else
  $(info CAMERA_CONFIG = $(CAMERA_CONFIG))
  $(shell echo $(CAMERA_CONFIG) > $(BUILD_MEMO))
endif

# Ensure BOARD is set from CAMERA_CONFIG if not already set
BOARD ?= $(shell basename "$(CAMERA_CONFIG)" | sed -E "s/_defconfig//")
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

CAMERA = $(BOARD)
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
BOARD :=
CAMERA :=
$(info Board selection skipped for target: $(CURRENT_TARGETS))

endif
