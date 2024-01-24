################################################################################
#
# majestic
#
################################################################################

MAJESTIC_SITE = https://openipc.s3-eu-west-1.amazonaws.com
MAJESTIC_SOURCE = majestic.$(MAJESTIC_FAMILY).$(MAJESTIC_RELEASE).master.tar.bz2

MAJESTIC_LICENSE = PROPRIETARY
MAJESTIC_LICENSE_FILES = LICENSE

$(eval MAJESTIC_FAMILY = $(patsubst "%",%,$(SOC_FAMILY)))

ifeq ($(MAJESTIC_FAMILY),t10)
	MAJESTIC_FAMILY= t21
endif

MAJESTIC_RELEASE = lite
MAJESTIC_DEPENDENCIES = \
	json-c \
	libevent-openipc \
	libogg \
	opus \
	mbedtls \
	mxml \
	zlib
#	lame

MAJESTIC_STRIP_COMPONENTS = 0

define MAJESTIC_INSTALL_TARGET_CMDS
	$(INSTALL) -m 755 -d $(TARGET_DIR)/etc
	$(INSTALL) -m 644 $(@D)/majestic-mini.yaml $(TARGET_DIR)/etc/majestic.yaml
	$(INSTALL) -m 644 $(@D)/majestic.yaml $(TARGET_DIR)/etc/majestic.full

	$(INSTALL) -m 755 -d $(TARGET_DIR)/etc/init.d
	$(INSTALL) -m 755 -t $(TARGET_DIR)/etc/init.d $(MAJESTIC_PKGDIR)/files/S95majestic

	$(INSTALL) -m 755 -d $(TARGET_DIR)/usr/bin
	$(INSTALL) -m 755 -t $(TARGET_DIR)/usr/bin $(@D)/majestic

	# Majestic is compiled for older libmbedtls
	[ ! -f "$(TARGET_DIR)/usr/lib/libmbedtls.so.13" ] && ln -srfv $(TARGET_DIR)/usr/lib/libmbedtls.so.14 $(TARGET_DIR)/usr/lib/libmbedtls.so.13
	[ ! -f "$(TARGET_DIR)/usr/lib/libmbedcrypto.so.6" ] && ln -srfv $(TARGET_DIR)/usr/lib/libmbedcrypto.so.7 $(TARGET_DIR)/usr/lib/libmbedcrypto.so.6

	rm -rf $(MAJESTIC_DL_DIR)
endef

$(eval $(generic-package))
