THINGINO_PRUSA_CONNECT_SITE_METHOD = local
THINGINO_PRUSA_CONNECT_SITE = $(BR2_EXTERNAL)/package/thingino-prusa-connect

define THINGINO_PRUSA_CONNECT_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(THINGINO_PRUSA_CONNECT_PKGDIR)/files/prusa-connectd \
		$(TARGET_DIR)/usr/sbin/prusa-connectd

	$(INSTALL) -D -m 0755 $(THINGINO_PRUSA_CONNECT_PKGDIR)/files/prusa-connect \
		$(TARGET_DIR)/usr/sbin/prusa-connect

	$(INSTALL) -D -m 0755 $(THINGINO_PRUSA_CONNECT_PKGDIR)/files/S67prusa-connect \
		$(TARGET_DIR)/etc/init.d/S67prusa-connect

	$(INSTALL) -D -m 0644 $(THINGINO_PRUSA_CONNECT_PKGDIR)/files/prusa-connect.json \
		$(TARGET_DIR)/etc/prusa-connect.json

	$(INSTALL) -d -m 0755 $(TARGET_DIR)/var/lib/prusa-connect

	$(INSTALL) -D -m 0755 $(THINGINO_PRUSA_CONNECT_PKGDIR)/files/www/x/service-prusa-connect.cgi \
		$(TARGET_DIR)/var/www/x/service-prusa-connect.cgi
endef

$(eval $(generic-package))
