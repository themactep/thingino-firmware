LIST_OF_CAMERAS := $(shell find $(CAMERA_SUBDIR) -type f -name '*_defconfig' | \
	sed -E "s/^(.+)\/(.*)_defconfig/'\0' '\2'/" | sort)

BUILD_MEMO := /tmp/thingino-board.$(shell ps -o ppid $$PPID | tail -1 | xargs)

ifeq ($(BOARD),)
  ifeq ($(shell test -f $(BUILD_MEMO); echo $$?), 0)
    CAMERA_CONFIG = $(shell cat $(BUILD_MEMO))
    ifneq ($(CAMERA_CONFIG),)
      BOARD ?= $(shell basename "$(CAMERA_CONFIG)" | sed -E "s/_defconfig//")
      ifeq ($(shell whiptail --yesno "Use $(BOARD)?" 20 76 3>&1 1>&2 2>&3; echo $$?),1)
        CAMERA_CONFIG =
        $(shell rm $(BUILD_MEMO))
      endif
    endif
  endif
else
  CAMERA_CONFIG = $(shell find $(CAMERA_SUBDIR) -name "$(BOARD)_defconfig")
endif

ifeq ($(CAMERA_CONFIG),)
  CAMERA_CONFIG := $(or $(shell whiptail --title "Config files" \
	--menu "Select a camera config:" 20 76 12 \
	--notags $(LIST_OF_CAMERAS) 3>&1 1>&2 2>&3))
endif

ifeq ($(CAMERA_CONFIG),)
  $(error * config file not found)
else ifneq ($(shell echo "$(CAMERA_CONFIG)" | wc -w), 1)
  $(error * found multiple config files: $(CAMERA_CONFIG))
else
  $(info CAMERA_CONFIG = $(CAMERA_CONFIG))
  $(shell echo $(CAMERA_CONFIG) > $(BUILD_MEMO))
endif

BOARD ?= $(shell basename "$(CAMERA_CONFIG)" | sed -E "s/_defconfig//")
CAMERA_CONFIG_REAL := $(shell realpath "$(BR2_EXTERNAL)/$(CAMERA_CONFIG)")
$(info CAMERA_CONFIG_REAL = $(CAMERA_CONFIG_REAL))

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
