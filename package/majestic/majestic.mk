################################################################################
#
# majestic
#
################################################################################

MAJESTIC_LICENSE = PROPRIETARY
MAJESTIC_LICENSE_FILES = LICENSE

$(eval MAJESTIC_FAMILY = $(patsubst "%",%,$(SOC_FAMILY)))
ifeq ($(MAJESTIC_FAMILY),t10)
	MAJESTIC_FAMILY= t21
endif

MAJESTIC_RELEASE = lite

ifeq ($(BR2_SOC_INGENIC_T20),y)
MAJESTIC_DEPENDENCIES += \
	libevent-openipc \
	libogg-openipc \
	mbedtls-openipc \
	opus-openipc \
else
MAJESTIC_DEPENDENCIES += \
	libevent \
	libogg \
	opus \
	mbedtls \
	mxml \
	zlib
endif
MAJESTIC_DEPENDENCIES += \
	json-c

define MAJESTIC_INSTALL_TARGET_CMDS
	$(INSTALL) -m 755 -d $(TARGET_DIR)/etc
	$(INSTALL) -m 644 -t $(TARGET_DIR)/etc $(MAJESTIC_PKGDIR)/files/majestic.yaml

	$(INSTALL) -m 755 -d $(TARGET_DIR)/etc/init.d
	$(INSTALL) -m 755 -t $(TARGET_DIR)/etc/init.d $(MAJESTIC_PKGDIR)/files/S95majestic

	$(INSTALL) -m 755 -d $(TARGET_DIR)/usr/bin
	$(INSTALL) -m 755 -t $(TARGET_DIR)/usr/bin $(MAJESTIC_PKGDIR)/files/$(MAJESTIC_RELEASE)/$(MAJESTIC_FAMILY)/majestic

	$(INSTALL) -m 755 -d $(TARGET_DIR)/usr/share/fonts/truetype
	$(INSTALL) -m 644 -t $(TARGET_DIR)/usr/share/fonts/truetype $(MAJESTIC_PKGDIR)/files/UbuntuMono-Regular.ttf

	# Majestic is compiled for older libmbedtls
	#[ ! -f "$(TARGET_DIR)/usr/lib/libmbedtls.so.13" ] && ln -srfv $(TARGET_DIR)/usr/lib/libmbedtls.so.14 $(TARGET_DIR)/usr/lib/libmbedtls.so.13
	#[ ! -f "$(TARGET_DIR)/usr/lib/libmbedcrypto.so.6" ] && ln -srfv $(TARGET_DIR)/usr/lib/libmbedcrypto.so.7 $(TARGET_DIR)/usr/lib/libmbedcrypto.so.6
endef

$(eval $(generic-package))
