LINUX_EXTENSIONS += thingino-kopt

# Run the LED header/patch hook after patches: the cumulative thingino
# kernel patch ships its own board_base.c, which overwrites the changes
# made by the PRE_PATCH hook.
LINUX_POST_PATCH_HOOKS += THINGINO_KOPT_PREPARE_KERNEL

THINGINO_LED_CONFIG = $(BR2_CONFIG)
THINGINO_LED_HEADER = $(LINUX_DIR)/arch/mips/xburst/soc-$(SOC_FAMILY)/chip-$(SOC_FAMILY)/isvp/common/thingino_leds.h
THINGINO_LED_BOARD_BASE = $(LINUX_DIR)/arch/mips/xburst/soc-$(SOC_FAMILY)/chip-$(SOC_FAMILY)/isvp/common/board_base.c

define THINGINO_KOPT_PREPARE_KERNEL
	sh $(BR2_EXTERNAL_THINGINO_PATH)/scripts/generate_kernel_led_header.sh \
		$(THINGINO_LED_CONFIG) \
		$(THINGINO_LED_HEADER) \
		'$(CAMERA_DTSI_FILE)'
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

# Per-device dtsi fragment from the camera profile dir (CAMERA_DTSI_FILE comes
# from thingino.mk). The injector finds the leaf .dts the kernel config builds,
# copies the fragment in and #includes it, 4.4 and later only: a 3.10 tree has
# no device-tree directory and is left untouched. It also skips a leaf whose
# tree lacks the labels the fragment needs, so an ahead-of-time fragment cannot
# break a family that has no 4.4 tree yet. Runs after the .dts sync above.
ifneq ($(CAMERA_DTSI_FILE),)
ifneq ($(KERNEL_VERSION),3.10.14)
define THINGINO_KOPT_SYNC_CAMERA_DTSI
	sh $(BR2_EXTERNAL_THINGINO_PATH)/package/thingino-kopt/inject-camera-dtsi.sh \
		$(CAMERA_DTSI_FILE) $(LINUX_DIR)
endef
LINUX_PRE_BUILD_HOOKS += THINGINO_KOPT_SYNC_CAMERA_DTSI
endif
endif

# The DWC2 driver needs its controller and PHY enabled in the 4.4 device
# tree too, which most vendor trees ship disabled. Runs after the sync above
# so a profile's own .dts is covered.
ifeq ($(BR2_PACKAGE_THINGINO_KOPT_DWC2),y)
define THINGINO_KOPT_USB_DT
	sh $(BR2_EXTERNAL_THINGINO_PATH)/package/thingino-kopt/inject-usb-dt.sh \
		$(LINUX_DIR) $(if $(BR2_PACKAGE_THINGINO_KOPT_DWC2_DUAL_ROLE),otg,host)
endef
LINUX_PRE_BUILD_HOOKS += THINGINO_KOPT_USB_DT
endif
