################################################################################
#
# thingino-isp-inspector
#
################################################################################

THINGINO_ISP_INSPECTOR_SITE_METHOD = local
THINGINO_ISP_INSPECTOR_SITE = $(THINGINO_ISP_INSPECTOR_PKGDIR)/files
THINGINO_ISP_INSPECTOR_LICENSE = MIT

ifeq ($(BR2_PACKAGE_THINGINO_WEBUI),y)
THINGINO_ISP_INSPECTOR_DEPENDENCIES += thingino-webui

define THINGINO_ISP_INSPECTOR_INSTALL_WWW_CMDS
	$(INSTALL) -d $(TARGET_DIR)/var/www/a
	$(INSTALL) -d $(TARGET_DIR)/var/www/x
	$(INSTALL) -d $(TARGET_DIR)/var/www/a/plugins

	$(INSTALL) -D -m 0644 $(THINGINO_ISP_INSPECTOR_PKGDIR)/files/www/config-isp-inspector.html \
		$(TARGET_DIR)/var/www/config-isp-inspector.html
	$(INSTALL) -D -m 0644 $(THINGINO_ISP_INSPECTOR_PKGDIR)/files/www/a/config-isp-inspector.js \
		$(TARGET_DIR)/var/www/a/config-isp-inspector.js
	$(INSTALL) -D -m 0755 $(THINGINO_ISP_INSPECTOR_PKGDIR)/files/www/x/json-isp-m0.cgi \
		$(TARGET_DIR)/var/www/x/json-isp-m0.cgi
	$(INSTALL) -D -m 0755 $(THINGINO_ISP_INSPECTOR_PKGDIR)/files/www/x/json-isp-fs.cgi \
		$(TARGET_DIR)/var/www/x/json-isp-fs.cgi
	$(INSTALL) -D -m 0755 $(THINGINO_ISP_INSPECTOR_PKGDIR)/files/www/x/isp-sse.cgi \
		$(TARGET_DIR)/var/www/x/isp-sse.cgi

	$(INSTALL) -D -m 0644 $(THINGINO_ISP_INSPECTOR_PKGDIR)/files/thingino-isp-inspector.webui.json \
		$(TARGET_DIR)/var/www/a/plugins/thingino-isp-inspector.webui.json
endef
endif

define THINGINO_ISP_INSPECTOR_INSTALL_TARGET_CMDS
	$(THINGINO_ISP_INSPECTOR_INSTALL_WWW_CMDS)
endef

$(eval $(generic-package))
