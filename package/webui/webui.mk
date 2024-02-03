################################################################################
#
# webui
#
################################################################################

WEBUI_SITE_METHOD = git
WEBUI_SITE = https://github.com/themactep/wehaveopenipcathome-webui
WEBUI_VERSION = $(shell git ls-remote $(WEBUI_SITE) HEAD | head -1 | cut -f1)

WEBUI_LICENSE = MIT
WEBUI_LICENSE_FILES = LICENSE

define WEBUI_INSTALL_TARGET_CMDS
	$(INSTALL) -m 755 -d $(TARGET_DIR)/var
	cp -rv $(@D)/www $(TARGET_DIR)/var

	$(INSTALL) -m 755 -d $(TARGET_DIR)/etc
	$(INSTALL) -m 644 -t $(TARGET_DIR)/etc $(WEBUI_PKGDIR)/files/httpd.conf

	$(INSTALL) -m 755 -d $(TARGET_DIR)/etc/init.d
	$(INSTALL) -m 755 -t $(TARGET_DIR)/etc/init.d $(WEBUI_PKGDIR)/files/S50httpd
endef

$(eval $(generic-package))
