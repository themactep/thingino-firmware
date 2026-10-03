THINGINO_ISP_GUARD_SITE_METHOD = local
THINGINO_ISP_GUARD_SITE = $(BR2_EXTERNAL_THINGINO_PATH)/package/thingino-isp-guard

define THINGINO_ISP_GUARD_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(THINGINO_ISP_GUARD_PKGDIR)/files/S10isp-guard \
		$(TARGET_DIR)/etc/init.d/S10isp-guard
endef

$(eval $(generic-package))
