################################################################################
#
# thingino-odhcp6c
#
################################################################################

THINGINO_ODHCP6C_VERSION = 24485bb4b35ab84c17c2e87bd561d026d4c15c00
THINGINO_ODHCP6C_SITE = https://git.openwrt.org/project/odhcp6c.git
THINGINO_ODHCP6C_SITE_METHOD = git
THINGINO_ODHCP6C_LICENSE = GPL-2.0
THINGINO_ODHCP6C_LICENSE_FILES = COPYING
THINGINO_ODHCP6C_DEPENDENCIES = thingino-libubox

define THINGINO_ODHCP6C_INSTALL_SCRIPT
	$(INSTALL) -m 0755 -D $(@D)/odhcp6c-example-script.sh \
		$(TARGET_DIR)/usr/sbin/odhcp6c-update
endef

THINGINO_ODHCP6C_POST_INSTALL_TARGET_HOOKS += THINGINO_ODHCP6C_INSTALL_SCRIPT

$(eval $(cmake-package))
