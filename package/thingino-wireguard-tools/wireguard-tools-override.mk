################################################################################
#
# wireguard-tools overrides for Thingino
#
################################################################################

ifeq ($(BR2_PACKAGE_WIREGUARD_TOOLS),y)

override WIREGUARD_TOOLS_VERSION = 1.0.20260223
override WIREGUARD_TOOLS_SOURCE = wireguard-tools-$(WIREGUARD_TOOLS_VERSION).tar.xz
override WIREGUARD_TOOLS_SITE = https://git.zx2c4.com/wireguard-tools/snapshot

# Use Thingino-maintained hash file when version is overridden.
override WIREGUARD_TOOLS_HASH_FILES = \
	$(THINGINO_EXTERNAL_PATH)/package/all-patches/wireguard-tools/wireguard-tools.hash

endif # BR2_PACKAGE_WIREGUARD_TOOLS
