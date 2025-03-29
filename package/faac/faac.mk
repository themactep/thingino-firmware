FAAC_SITE_METHOD = git
FAAC_SITE = https://github.com/knik0/faac
FAAC_SITE_BRANCH = master
FAAC_VERSION = 0ef84165678c406da2e2dcd57c1ecb176f416771
# $(shell git ls-remote $(FAAC_SITE) $(FAAC_SITE_BRANCH) | head -1 | cut -f1)

FAAC_LICENSE = MPEG-4-Reference-Code, LGPL-2.1+
FAAC_LICENSE_FILES = COPYING

FAAC_INSTALL_STAGING = YES
FAAC_INSTALL_TARGET = YES

FAAC_AUTORECONF = YES
FAAC_DEPENDENCIES += host-pkgconf host-libtool

FAAC_CONF_OPTS = --prefix=/usr --enable-shared --disable-static

FAAC_LDFLAGS = $(TARGET_LDFLAGS) -z max-page-size=0x1000
FAAC_CONF_ENV = PKG_CONFIG="$(PKG_CONFIG_HOST_BINARY)" LDFLAGS="$(FAAC_LDFLAGS)"

define FAAC_CONFIGURE_CMDS
	(cd $(FAAC_SRCDIR) && rm -rf config.cache && \
	$(TARGET_CONFIGURE_OPTS) \
	$(TARGET_CONFIGURE_ARGS) \
	$(FAAC_CONF_ENV) \
	./configure \
		--host=$(GNU_TARGET_NAME) \
		--build=$(GNU_HOST_NAME) \
		--target=$(GNU_TARGET_NAME) \
		$(FAAC_CONF_OPTS) \
	)
endef

define FAAC_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/libfaac/.libs/libfaac.so.0.0.0 \
		$(TARGET_DIR)/usr/lib/libfaac.so.0.0.0

	ln -sf libfaac.so.0.0.0 $(TARGET_DIR)/usr/lib/libfaac.so.0
	ln -sf libfaac.so.0.0.0 $(TARGET_DIR)/usr/lib/libfaac.so
endef

define FAAC_INSTALL_STAGING_CMDS
	$(INSTALL) -D -m 0644 $(@D)/include/faac.h \
		$(STAGING_DIR)/usr/include/faac.h

	$(INSTALL) -D -m 0644 $(@D)/include/faaccfg.h \
		$(STAGING_DIR)/usr/include/faaccfg.h

	$(INSTALL) -D -m 0755 $(@D)/libfaac/.libs/libfaac.so.0.0.0 \
		$(STAGING_DIR)/usr/lib/libfaac.so.0.0.0

	ln -sf libfaac.so.0.0.0 $(STAGING_DIR)/usr/lib/libfaac.so.0
	ln -sf libfaac.so.0.0.0 $(STAGING_DIR)/usr/lib/libfaac.so
endef

$(eval $(autotools-package))
$(eval $(host-autotools-package))
