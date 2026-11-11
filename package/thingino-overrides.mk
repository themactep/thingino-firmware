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
#
# This file is parsed via BR2_PACKAGE_OVERRIDE_FILE before Buildroot re-includes
# .br2-external.mk with unquoted values (buildroot/Makefile), so the path may
# still be quoted here. Use the quote-stripped alias for parse-time includes;
# elsewhere (recipes, hooks, other .mk files) use BR2_EXTERNAL_THINGINO_PATH
# directly - it is always defined and unquoted by the time those expand.
THINGINO_OVERRIDE_DIR := $(patsubst "%",%,$(strip $(BR2_EXTERNAL_THINGINO_PATH)))
-include $(THINGINO_OVERRIDE_DIR)/local.mk
-include $(CONFIG_DIR)/local.mk

include $(THINGINO_OVERRIDE_DIR)/package/thingino-webserver/busybox-httpd-override.mk
include $(THINGINO_OVERRIDE_DIR)/package/thingino-ethernet/busybox-ifplugd-override.mk
include $(THINGINO_OVERRIDE_DIR)/package/thingino-freetype/freetype-override.mk
include $(THINGINO_OVERRIDE_DIR)/package/thingino-libcurl/libcurl-override.mk
include $(THINGINO_OVERRIDE_DIR)/package/thingino-libopenssl/libopenssl-override.mk
include $(THINGINO_OVERRIDE_DIR)/package/thingino-libwebsockets/libwebsockets-override.mk
include $(THINGINO_OVERRIDE_DIR)/package/thingino-live555/live555-override.mk
include $(THINGINO_OVERRIDE_DIR)/package/thingino-mbedtls/mbedtls-override.mk
include $(THINGINO_OVERRIDE_DIR)/package/thingino-mosquitto-212/mosquitto-override.mk
include $(THINGINO_OVERRIDE_DIR)/package/thingino-mxml/mxml-override.mk
include $(THINGINO_OVERRIDE_DIR)/package/thingino-v4l2loopback/v4l2loopback-override.mk
include $(THINGINO_OVERRIDE_DIR)/package/thingino-wireguard-tools/wireguard-tools-override.mk
include $(THINGINO_OVERRIDE_DIR)/package/thingino-wpa_supplicant/wpa_supplicant-override.mk
