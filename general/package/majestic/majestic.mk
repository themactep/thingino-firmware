################################################################################
#
# majestic
#
################################################################################

MAJESTIC_VERSION = current
MAJESTIC_SITE = https://openipc.s3-eu-west-1.amazonaws.com
MAJESTIC_LICENSE = PROPRIETARY
MAJESTIC_LICENSE_FILES = LICENSE

$(eval FAMILY := $(patsubst "%",%,$(BR2_OPENIPC_SOC_FAMILY)))
ifeq ($(FAMILY),t10)
	FAMILY := t21
endif

$(eval RELEASE := $(patsubst "%",%,$(BR2_OPENIPC_SOC_FLAVOR)))
ifeq ($(RELEASE),y)
	RELEASE := ultimate
	# we don't have Majestic binary Ultimate distributions for these
	# platforms so use Lite
	ifeq ($(FAMILY),hi3516av100)
		RELEASE := lite
	else ifeq ($(FAMILY),hi3519v101)
		RELEASE := lite
	endif
else ifeq ($(BR2_OPENIPC_FLAVOR_FPV),y)
	RELEASE := fpv
else ifeq ($(BR2_OPENIPC_FLAVOR_LITE),y)
	RELEASE := lite
else ifeq ($(BR2_OPENIPC_FLAVOR_ULTIMATE),y)
	RELEASE := ultimate
else
	# default
	RELEASE := wtf
endif

ifeq ($(RELEASE),lte)
	RELEASE := fpv
endif

MAJESTIC_SOURCE := majestic.$(FAMILY).$(RELEASE).master.tar.bz2

MAJESTIC_DEPENDENCIES = \
	libevent-openipc \
	json-c \
	mbedtls \
	mxml \
	zlib

ifneq ($(BR2_OPENIPC_FLAVOR_FPV),y)
MAJESTIC_DEPENDENCIES += \
	libogg \
	opus
endif

ifeq ($(BR2_OPENIPC_FLAVOR_ULTIMATE),y)
MAJESTIC_DEPENDENCIES += \
	lame
endif

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
endef

define MAJESTIC_REMOVE_DOWNLOAD
	rm -f $(BR2_DL_DIR)/majestic/$(MAJESTIC_SOURCE)
endef
MAJESTIC_PRE_DOWNLOAD_HOOKS += MAJESTIC_REMOVE_DOWNLOAD

$(eval $(generic-package))
