################################################################################
# telegrambot
################################################################################

TELEGRAMBOT_VERSION = 1.0
TELEGRAMBOT_SITE = $(TELEGRAMBOT_PKGDIR)/files
TELEGRAMBOT_SITE_METHOD = local
TELEGRAMBOT_LICENSE = MIT

TELEGRAMBOT_DEPENDENCIES = thingino-libcurl thingino-jct
# Package-specific flags (append-only for configurability)
TELEGRAMBOT_CFLAGS += -D_POSIX_C_SOURCE=200809L -std=c99 \
	-Wall -Wextra -Os -ffunction-sections -fdata-sections \
	-I$(STAGING_DIR)/usr/include

TELEGRAMBOT_LDFLAGS += -Wl,--gc-sections
# Link libraries (append-only for configurability)
TELEGRAMBOT_LIBS += -L$(STAGING_DIR)/usr/lib -ljct -lcurl



define TELEGRAMBOT_BUILD_CMDS
	$(TARGET_CC) $(TARGET_CFLAGS) $(TELEGRAMBOT_CFLAGS) \
		-c $(@D)/telegrambot.c \
		-o $(@D)/telegrambot.o

	$(TARGET_CC) $(TARGET_LDFLAGS) $(TELEGRAMBOT_LDFLAGS) -o $(@D)/telegrambot \
		$(@D)/telegrambot.o $(TELEGRAMBOT_LIBS)
endef

define TELEGRAMBOT_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/telegrambot \
		$(TARGET_DIR)/usr/sbin/telegrambot
	$(INSTALL) -D -m 0755 $(TELEGRAMBOT_PKGDIR)/files/etc/init.d/S93telegrambot \
		$(TARGET_DIR)/etc/init.d/S93telegrambot
	$(INSTALL) -D -m 0644 $(TELEGRAMBOT_PKGDIR)/files/etc/telegrambot.json \
		$(TARGET_DIR)/etc/telegrambot.json
	$(INSTALL) -D -m 0644 $(TELEGRAMBOT_PKGDIR)/files/www/a/telegrambot-ui.js \
		$(TARGET_DIR)/var/www/a/telegrambot-ui.js
	$(INSTALL) -D -m 0755 $(TELEGRAMBOT_PKGDIR)/files/www/x/service-telegrambot.cgi \
		$(TARGET_DIR)/var/www/x/service-telegrambot.cgi
	$(INSTALL) -D -m 0755 $(TELEGRAMBOT_PKGDIR)/files/www/x/json-telegrambot.cgi \
		$(TARGET_DIR)/var/www/x/json-telegrambot.cgi
	$(INSTALL) -D -m 0755 $(TELEGRAMBOT_PKGDIR)/files/www/x/ctl-telegrambot.cgi \
		$(TARGET_DIR)/var/www/x/ctl-telegrambot.cgi
endef

$(eval $(generic-package))
