SENSOR_MODELS = $()

ifeq ($(BR2_SENSOR_MODEL),)
ifeq ($(shell test -f .board; echo $$?),0)
BR2_SENSOR_MODEL = $(shell sed -n /SENSOR_MODEL:(\.*)/\1/p .board)
ifeq ($(shell whiptail --yesno "Use $(SENSOR_MODEL) from the previous session?" 10 40 3>&1 1>&2 2>&3; echo $$?),1)
BR2_SENSOR_MODEL =
$(shell sed /SENSOR_MODEL:(.*)/d .board)
endif
endif
endif

# if still no BOARD, select it from a list of boards
ifeq ($(BR2_SENSOR_MODEL),)
BR2_SENSOR_MODEL := $(or $(shell whiptail --title "Sensors" --menu "Select a sensor:" 20 76 12 --notags $(SENSOR_MODELS) 3>&1 1>&2 2>&3))
endif
