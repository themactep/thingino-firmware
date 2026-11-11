################################################################################
#
# thingino-send2
#
################################################################################

THINGINO_SEND2_SITE_METHOD = local
THINGINO_SEND2_SITE = $(BR2_EXTERNAL_THINGINO_PATH)/package/thingino-send2
THINGINO_SEND2_LICENSE = MIT
THINGINO_SEND2_DEPENDENCIES = thingino-jct

define THINGINO_SEND2_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0644 $(@D)/files/send2.json \
		$(TARGET_DIR)/etc/send2.json
	$(INSTALL) -D -m 0644 $(@D)/files/prudynt-helpers \
		$(TARGET_DIR)/usr/share/prudynt-helpers
	$(INSTALL) -D -m 0644 $(@D)/files/send2common \
		$(TARGET_DIR)/usr/share/send2common
	for f in send2email send2ftp send2gphotos send2gotify send2mqtt \
		send2ntfy send2pushover send2storage send2telegram send2webhook; do \
		$(INSTALL) -D -m 0755 $(@D)/files/$$f \
			$(TARGET_DIR)/usr/sbin/$$f ; \
	done
endef

$(eval $(generic-package))
