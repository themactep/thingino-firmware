LINUX_EXTENSIONS += thingino-kopt

THINGINO_LED_CONFIG = $(BR2_CONFIG)
THINGINO_LED_HEADER = $(LINUX_DIR)/arch/mips/xburst/soc-$(SOC_FAMILY)/chip-$(SOC_FAMILY)/isvp/common/thingino_leds.h
THINGINO_LED_BOARD_BASE = $(LINUX_DIR)/arch/mips/xburst/soc-$(SOC_FAMILY)/chip-$(SOC_FAMILY)/isvp/common/board_base.c

define THINGINO_KOPT_PREPARE_KERNEL
	sh $(BR2_EXTERNAL_THINGINO_PATH)/scripts/generate_kernel_led_header.sh \
		$(THINGINO_LED_CONFIG) \
		$(THINGINO_LED_HEADER)
	sh $(BR2_EXTERNAL_THINGINO_PATH)/scripts/patch_kernel_leds_board_base.sh \
		$(THINGINO_LED_BOARD_BASE)
endef

# Per-device dts from the camera profile dir (CAMERA_DTS_FILE/DEST come
# from thingino.mk). Copied before every kernel build, so a profile
# change or dts edit can never leak a stale tree into the build.
ifneq ($(CAMERA_DTS_FILE),)
define THINGINO_KOPT_SYNC_CAMERA_DTS
	cp -f $(CAMERA_DTS_FILE) \
		$(LINUX_DIR)/arch/mips/boot/dts/ingenic/$(CAMERA_DTS_DEST).dts
endef
LINUX_PRE_BUILD_HOOKS += THINGINO_KOPT_SYNC_CAMERA_DTS
endif
