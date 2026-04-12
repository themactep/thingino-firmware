################################################################################
# subzeroclaw
################################################################################

SUBZEROCLAW_VERSION = 1d203dd4a896b02d521b300431c9127f2917d10a
SUBZEROCLAW_SITE = https://github.com/jmlago/subzeroclaw
SUBZEROCLAW_SITE_METHOD = git

SUBZEROCLAW_LICENSE = MIT
SUBZEROCLAW_LICENSE_FILES = LICENSE

SUBZEROCLAW_DEPENDENCIES = cjson thingino-libcurl

SUBZEROCLAW_CFLAGS += \
	-std=c11 -Wall -Wextra -O2 -D_GNU_SOURCE \
	-I$(STAGING_DIR)/usr/include

SUBZEROCLAW_LDFLAGS += \
	-L$(STAGING_DIR)/usr/lib \
	-lcjson -lcurl -lm

define SUBZEROCLAW_BUILD_CMDS
	$(TARGET_CC) $(TARGET_CFLAGS) $(SUBZEROCLAW_CFLAGS) \
		-o $(@D)/subzeroclaw $(@D)/src/subzeroclaw.c \
		$(TARGET_LDFLAGS) $(SUBZEROCLAW_LDFLAGS)
endef

define SUBZEROCLAW_INSTALL_TARGET_CMDS
	$(INSTALL) -d -m 0755 $(TARGET_DIR)/etc/subzeroclaw/skills
	$(INSTALL) -D -m 0755 $(@D)/subzeroclaw $(TARGET_DIR)/usr/bin/subzeroclaw
	$(INSTALL) -D -m 0644 $(SUBZEROCLAW_PKGDIR)/files/config $(TARGET_DIR)/etc/subzeroclaw/config
	$(INSTALL) -D -m 0644 $(SUBZEROCLAW_PKGDIR)/files/system.md $(TARGET_DIR)/etc/subzeroclaw/skills/system.md
endef

$(eval $(generic-package))
