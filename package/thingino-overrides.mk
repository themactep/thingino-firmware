################################################################################
#
# Thingino package overrides entry point
#
################################################################################

# Add new overrides here so we only need a single BR2_PACKAGE_OVERRIDE_FILE.
# Keep the includes alphabetized for readability.

# Allow developers to keep personal overrides in either the root local.mk
# (ignored by git) or the default $(CONFIG_DIR)/local.mk without losing this
# aggregated file.
THINGINO_EXTERNAL_PATH := $(patsubst "%",%,$(strip $(BR2_EXTERNAL_THINGINO_PATH)))
-include $(THINGINO_EXTERNAL_PATH)/local.mk
-include $(CONFIG_DIR)/local.mk

include $(THINGINO_EXTERNAL_PATH)/package/thingino-webserver/busybox-httpd-override.mk
include $(THINGINO_EXTERNAL_PATH)/package/thingino-freetype/freetype-override.mk
include $(THINGINO_EXTERNAL_PATH)/package/thingino-libcurl/libcurl-override.mk
include $(THINGINO_EXTERNAL_PATH)/package/thingino-libwebsockets/libwebsockets-override.mk
include $(THINGINO_EXTERNAL_PATH)/package/thingino-live555/live555-override.mk
include $(THINGINO_EXTERNAL_PATH)/package/thingino-mbedtls/mbedtls-override.mk
include $(THINGINO_EXTERNAL_PATH)/package/thingino-mosquitto-212/mosquitto-override.mk
include $(THINGINO_EXTERNAL_PATH)/package/thingino-mxml/mxml-override.mk
include $(THINGINO_EXTERNAL_PATH)/package/thingino-v4l2loopback/v4l2loopback-override.mk
