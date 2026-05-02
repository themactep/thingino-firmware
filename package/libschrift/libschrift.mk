LIBSCHRIFT_SITE_METHOD = git
LIBSCHRIFT_SITE = https://github.com/tomolt/libschrift
LIBSCHRIFT_SITE_BRANCH = master
LIBSCHRIFT_VERSION = 24737d2922b23df4a5692014f5ba03da0c296112

LIBSCHRIFT_INSTALL_STAGING = YES
LIBSCHRIFT_INSTALL_TARGET = NO

define LIBSCHRIFT_BUILD_CMDS
	$(TARGET_CC) -Os -std=c99 -pedantic -Wall -Wextra -Wconversion -c -o $(@D)/schrift.o $(@D)/schrift.c
	$(TARGET_AR) rcs $(@D)/libschrift.a $(@D)/schrift.o
endef

define LIBSCHRIFT_INSTALL_STAGING_CMDS
	$(INSTALL) -D -m 0644 $(@D)/libschrift.a \
		$(STAGING_DIR)/usr/lib/libschrift.a

	$(INSTALL) -D -m 0644 $(@D)/schrift.h \
		$(STAGING_DIR)/usr/include/schrift.h
endef

$(eval $(generic-package))
