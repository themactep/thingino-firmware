THINGINO_PKG_SITE_METHOD = local
THINGINO_PKG_SITE = $(BR2_EXTERNAL_THINGINO_PATH)/package/thingino-pkg

define THINGINO_PKG_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(THINGINO_PKG_PKGDIR)/files/thingino-pkg \
		$(TARGET_DIR)/usr/sbin/thingino-pkg
endef

$(eval $(generic-package))
