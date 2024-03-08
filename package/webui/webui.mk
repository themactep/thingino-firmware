################################################################################
#
# webui
#
################################################################################

WEBUI_SITE_METHOD = git
WEBUI_SITE = https://github.com/themactep/thingino-webui
ifeq ($(BR2_PACKAGE_MAJESTIC),y)
WEBUI_VERSION = $(shell git ls-remote $(WEBUI_SITE) majestic | head -1 | cut -f1)
else ifeq ($(BR2_PACKAGE_PRUDYNT_T),y)
WEBUI_VERSION = $(shell git ls-remote $(WEBUI_SITE) prudynt | head -1 | cut -f1)
else
WEBUI_VERSION = $(shell git ls-remote $(WEBUI_SITE) master | head -1 | cut -f1)
endif

WEBUI_LICENSE = MIT
WEBUI_LICENSE_FILES = LICENSE

define WEBUI_INSTALL_TARGET_CMDS
	$(INSTALL) -m 755 -d $(TARGET_DIR)/var
	cp -rv $(@D)/www $(TARGET_DIR)/var

	$(INSTALL) -m 755 -d $(TARGET_DIR)/etc
	$(INSTALL) -m 644 -t $(TARGET_DIR)/etc $(WEBUI_PKGDIR)/files/httpd.conf

	$(INSTALL) -m 755 -d $(TARGET_DIR)/etc/init.d
	$(INSTALL) -m 755 -t $(TARGET_DIR)/etc/init.d $(WEBUI_PKGDIR)/files/S50httpd

	if ! grep -q "^BR2_THINGINO_DEV_PACKAGES=y" $(BR2_CONFIG); then \
		$(INSTALL) -m 755 -t $(TARGET_DIR)/etc/init.d $(WEBUI_PKGDIR)/files/S44devmounts; \
	fi
endef

$(eval $(generic-package))
