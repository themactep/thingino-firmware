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
-include $(BR2_EXTERNAL)/local.mk
-include $(CONFIG_DIR)/local.mk

include $(BR2_EXTERNAL)/package/thingino-freetype/freetype-override.mk
include $(BR2_EXTERNAL)/package/thingino-libwebsockets/libwebsockets-override.mk
include $(BR2_EXTERNAL)/package/thingino-live555/live555-override.mk
include $(BR2_EXTERNAL)/package/thingino-mbedtls/mbedtls-override.mk
include $(BR2_EXTERNAL)/package/thingino-mosquitto/mosquitto-override.mk
include $(BR2_EXTERNAL)/package/thingino-mxml/mxml-override.mk
