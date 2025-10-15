################################################################################
# telegrambot
################################################################################

TELEGRAMBOT_VERSION = 1.0
TELEGRAMBOT_SITE = $(TELEGRAMBOT_PKGDIR)/files
TELEGRAMBOT_SITE_METHOD = local
TELEGRAMBOT_LICENSE = MIT

TELEGRAMBOT_DEPENDENCIES = thingino-libcurl thingino-jct

define TELEGRAMBOT_BUILD_CMDS
	$(TARGET_CC) $(TARGET_CFLAGS) -D_POSIX_C_SOURCE=200809L -std=c99 \
		-Wall -Wextra -Os -ffunction-sections -fdata-sections \
		-I$(@D)/../.. \
		-I$(STAGING_DIR)/usr/include \
		-c $(@D)/telegrambot.c \
		-o $(@D)/telegrambot.o

	$(TARGET_CC) $(TARGET_LDFLAGS) -Wl,--gc-sections -o $(@D)/telegrambot \
		$(@D)/telegrambot.o -L$(STAGING_DIR)/usr/lib -ljct -lcurl
endef

define TELEGRAMBOT_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/telegrambot \
		$(TARGET_DIR)/usr/sbin/telegrambot
	$(INSTALL) -D -m 0755 $(TELEGRAMBOT_PKGDIR)/files/etc/init.d/S93telegrambot \
		$(TARGET_DIR)/etc/init.d/S93telegrambot
	$(INSTALL) -D -m 0644 $(TELEGRAMBOT_PKGDIR)/files/etc/telegrambot.json \
		$(TARGET_DIR)/etc/telegrambot.json
	$(INSTALL) -D -m 0755 $(TELEGRAMBOT_PKGDIR)/files/www/a/telegrambot-ui.js \
		$(TARGET_DIR)/var/www/a/telegrambot-ui.js
	$(INSTALL) -D -m 0755 $(TELEGRAMBOT_PKGDIR)/files/www/x/service-telegrambot.cgi \
		$(TARGET_DIR)/var/www/x/service-telegrambot.cgi
	$(INSTALL) -D -m 0755 $(TELEGRAMBOT_PKGDIR)/files/www/x/json-telegrambot.cgi \
		$(TARGET_DIR)/var/www/x/json-telegrambot.cgi
	$(INSTALL) -D -m 0755 $(TELEGRAMBOT_PKGDIR)/files/www/x/ctl-telegrambot.cgi \
		$(TARGET_DIR)/var/www/x/ctl-telegrambot.cgi
endef

$(eval $(generic-package))
