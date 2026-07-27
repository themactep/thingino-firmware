CAPJPEG_SITE_METHOD = git
CAPJPEG_SITE = https://github.com/openipc/capjpeg
CAPJPEG_SITE_BRANCH = main
CAPJPEG_VERSION = 77e9823935812605e5ea2fa10e227a1aa21d2253
# $(shell git ls-remote $(CAPJPEG_SITE) $(CAPJPEG_SITE_BRANCH) | head -1 | cut -f1)

CAPJPEG_LICENSE = MIT
CAPJPEG_LICENSE_FILES = LICENSE

define CAPJPEG_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/capJPEG \
		$(TARGET_DIR)/usr/bin/capjpeg
endef

$(eval $(generic-package))
