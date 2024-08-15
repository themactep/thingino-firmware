THINGINO_BUTTON_SITE_METHOD = git
THINGINO_BUTTON_SITE = https://github.com/gtxaspec/thingino-button
THINGINO_BUTTON_SITE_BRANCH = master
THINGINO_BUTTON_VERSION = $(shell git ls-remote $(THINGINO_BUTTON_SITE) $(THINGINO_BUTTON_SITE_BRANCH) | head -1 | cut -f1)

define THINGINO_BUTTON_BUILD_CMDS
	$(MAKE) $(TARGET_CONFIGURE_OPTS) -C $(@D) thingino-button
endef

define THINGINO_BUTTON_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/thingino-button $(TARGET_DIR)/usr/bin/thingino-button
	$(INSTALL) -m 0755 -D $(THINGINO_BUTTON_PKGDIR)/files/S15thingino-button $(TARGET_DIR)/etc/init.d/S15thingino-button
	$(INSTALL) -m 0644 -D $(THINGINO_BUTTON_PKGDIR)/files/thingino-button.conf $(TARGET_DIR)/etc/thingino-button.conf
endef

$(eval $(generic-package))
