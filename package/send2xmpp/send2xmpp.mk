################################################################################
#
# send2xmpp
#
################################################################################

SEND2XMPP_VERSION = 1.0.0
SEND2XMPP_SITE_METHOD = local
SEND2XMPP_SITE = $(BR2_EXTERNAL_THINGINO_PATH)/package/send2xmpp
SEND2XMPP_LICENSE = MIT

define SEND2XMPP_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/files/send2xmpp \
		$(TARGET_DIR)/usr/sbin/send2xmpp
	$(INSTALL) -D -m 0644 $(@D)/files/send2xmpp.conf.example \
		$(TARGET_DIR)/etc/send2xmpp.conf.example
	$(INSTALL) -D -m 0644 $(@D)/files/QUICKSTART.md \
		$(TARGET_DIR)/usr/share/doc/send2xmpp/QUICKSTART.md
endef

$(eval $(generic-package))
