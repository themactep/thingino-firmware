LIGHTNVR_SITE_METHOD = git
LIGHTNVR_SITE = https://github.com/opensensor/lightNVR
LIGHTNVR_SITE_BRANCH = main
LIGHTNVR_VERSION = $(shell git ls-remote $(LIGHTNVR_SITE) $(LIGHTNVR_SITE_BRANCH) | head -1 | cut -f1)

LIGHTNVR_LICENSE = GPL-2.0
LIGHTNVR_LICENSE_FILES = COPYING

LIGHTNVR_INSTALL_STAGING = YES

LIGHTNVR_DEPENDENCIES = thingino-ffmpeg sqlite

define LIGHTNVR_INSTALL_CONFIGS
	$(INSTALL) -d $(TARGET_DIR)/var/nvr
	cp -r $(@D)/web $(TARGET_DIR)/var/nvr/
	$(INSTALL) -m 755 -d $(TARGET_DIR)/etc
	$(INSTALL) -m 644 $(@D)/config/lightnvr.ini $(TARGET_DIR)/etc/lightnvr.ini
endef
LIGHTNVR_POST_INSTALL_TARGET_HOOKS += LIGHTNVR_INSTALL_CONFIGS


$(eval $(cmake-package))
