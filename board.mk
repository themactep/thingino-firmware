$(info --- FILE: board.mk ---)

LIST_OF_CAMERAS := $(shell find ./configs/cameras/* | sort | sed -E "s/^\.\/configs\/cameras\/(.*)/'cameras\/\1' '\1'/")
LIST_OF_MODULES := $(shell find ./configs/modules/* | sort | sed -E "s/^\.\/configs\/modules\/(.*)/'modules\/\1' '\1'/")
LIST_OF_TESTING := $(shell find ./configs/testing/* | sort | sed -E "s/^\.\/configs\/testing\/(.*)/'testing\/\1' '\1'/")

BUILD_MEMO := /tmp/thingino-board.$(shell ps -o ppid $$PPID | tail -1 | xargs)

ifeq ($(BOARD),)
 $(info * no BOARD in command line)
 $(info * search for a MEMO file from previous build)
 ifeq ($(shell test -f $(BUILD_MEMO); echo $$?), 0)
  $(info * MEMO file found: $(BUILD_MEMO))
  CAMERA_CONFIG = $(shell cat $(BUILD_MEMO))
  ifeq ($(CAMERA_CONFIG),)
   $(info * MEMO is empty)
   $(info * delete the MEMO file)
   $(shell rm $(BUILD_MEMO))
  else
   $(info * MEMO contains $(CAMERA_CONFIG))
   $(info * confirm the CAMERA_CONFIG)
   ifeq ($(shell whiptail --yesno "Use $(CAMERA_CONFIG) from the previous session?" 20 76 3>&1 1>&2 2>&3; echo $$?),1)
    $(info * discard CAMERA_CONFIG)
    CAMERA_CONFIG =
    $(info * delete the MEMO file)
    $(shell rm $(BUILD_MEMO))
   else
    $(info * reuse CAMERA_CONFIG from the MEMO)
   endif
  endif
 endif
else
 $(info * found BOARD "$(BOARD)" in command line)
 $(info * search for matching config files)
 CAMERA_CONFIG = $(shell find ./configs/modules ./configs/cameras ./configs/github ./configs/testing -name "$(BOARD)" | sed 's/\.\/configs\///')
endif

ifeq ($(CAMERA_CONFIG),)
 $(info * select CAMERA_CONFIG from a list)
 $(info $(LIST_OF_CAMERAS))
 $(info $(LIST_OF_MODULES))
 $(info $(LIST_OF_TESTING))
 CAMERA_CONFIG := $(or $(shell whiptail --title "Config files" \
	--menu "Select a camera or a board:" 20 76 12 --notags \
	" " "*----- CAMERAS ---------------------------*" \
	$(LIST_OF_CAMERAS) \
	" " "*----- MODULES ---------------------------*" \
	$(LIST_OF_MODULES) \
	" " "*----- EXPERIMENTAL CONFIGS --------------*" \
	$(LIST_OF_TESTING) \
	3>&1 1>&2 2>&3))
endif

ifeq ($(CAMERA_CONFIG),)
 $(error * config file not found)
else ifneq ($(shell echo "$(CAMERA_CONFIG)" | wc -w), 1)
 $(error * found multiple configs files: $(CAMERA_CONFIG))
else
 $(info CAMERA_CONFIG = $(CAMERA_CONFIG))
 $(info * save CAMERA_CONFIG to a MEMO file)
 $(shell echo $(CAMERA_CONFIG)>$(BUILD_MEMO))
endif

$(info * get real path to the config file)
CAMERA_CONFIG_REAL = $(shell realpath $(BR2_EXTERNAL)/configs/$(CAMERA_CONFIG))
$(info CAMERA_CONFIG_REAL = $(CAMERA_CONFIG_REAL))

MODULE_CONFIG = $(shell awk '/MODULE:/ {$$1=$$1;gsub(/^.+:\s*/,"");print}' $(CAMERA_CONFIG_REAL))
ifeq ($(MODULE_CONFIG),)
MODULE_CONFIG_REAL = $(CAMERA_CONFIG_REAL)
else
MODULE_CONFIG_REAL = $(shell realpath $(BR2_EXTERNAL)/configs/modules/$(MODULE_CONFIG))
endif

$(info MODULE_CONFIG = $(MODULE_CONFIG))

$(info * restore CAMERA for CAMERA_CONFIG)
CAMERA = $(shell basename $(CAMERA_CONFIG_REAL))
export CAMERA
$(info CAMERA = $(CAMERA))

# read camera config file
include $(CAMERA_CONFIG_REAL)

# read module config file
include $(MODULE_CONFIG_REAL)
