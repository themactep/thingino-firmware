################################################################################
#
# majestic
#
################################################################################

MAJESTIC_SITE = https://openipc.s3-eu-west-1.amazonaws.com
MAJESTIC_SOURCE = majestic.$(MAJESTIC_FAMILY).$(MAJESTIC_RELEASE).master.tar.bz2

MAJESTIC_LICENSE = PROPRIETARY
MAJESTIC_LICENSE_FILES = LICENSE

$(eval MAJESTIC_FAMILY = $(patsubst "%",%,$(BR2_OPENIPC_SOC_FAMILY)))
ifeq ($(MAJESTIC_FAMILY),t10)
	MAJESTIC_FAMILY= t21
endif

# we don't have Majestic ultimate for these platforms
MAJESTIC_LIST = hi3516av100 hi3519v101 t21

$(eval MAJESTIC_RELEASE = $(patsubst "%",%,$(BR2_OPENIPC_SOC_FLAVOR)))
ifeq ($(MAJESTIC_RELEASE),y)
	MAJESTIC_RELEASE = ultimate
else ifeq ($(BR2_OPENIPC_FLAVOR_FPV),y)
	MAJESTIC_RELEASE = fpv
else ifeq ($(BR2_OPENIPC_FLAVOR_LITE),y)
	MAJESTIC_RELEASE = lite
else ifeq ($(BR2_OPENIPC_FLAVOR_ULTIMATE),y)
	MAJESTIC_RELEASE = ultimate
else
	# default
	MAJESTIC_RELEASE = wtf
endif

ifneq ($(filter $(MAJESTIC_LIST),$(MAJESTIC_FAMILY)),)
	MAJESTIC_RELEASE = lite
endif

ifeq ($(MAJESTIC_RELEASE),lte)
	MAJESTIC_RELEASE = fpv
endif

MAJESTIC_DEPENDENCIES = \
	json-c \
	libevent-openipc \
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
