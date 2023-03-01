################################################################################
#
# majestic
#
################################################################################

MAJESTIC_VERSION = current
MAJESTIC_SITE = https://openipc.s3-eu-west-1.amazonaws.com
MAJESTIC_LICENSE = PROPRIETARY
MAJESTIC_LICENSE_FILES = LICENSE

FAMILY := $(shell grep "/board/" $(BR2_CONFIG) | head -1 | cut -d "/" -f 3)
# RELEASE := $(shell grep "BR2_DEFCONFIG" $(BR2_CONFIG) | head -1 | cut -d "/" -f 3 | cut -d "_" -f 2)

ifeq ($(BR2_OPENIPC_FLAVOR_ULTIMATE),y)
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
else
	# default
	RELEASE := wtf
endif

MAJESTIC_SOURCE := majestic.$(FAMILY).$(RELEASE).master.tar.bz2

MAJESTIC_DEPENDENCIES = \
	libevent-openipc \
	json-c-openipc \
	mbedtls-openipc \
	mxml \
	zlib

ifneq ($(BR2_OPENIPC_FLAVOR_FPV),y)
MAJESTIC_DEPENDENCIES += \
	libogg-openipc \
	opus-openipc
endif

ifeq ($(BR2_OPENIPC_FLAVOR_ULTIMATE),y)
MAJESTIC_DEPENDENCIES += \
	lame-openipc
endif

define MAJESTIC_INSTALL_TARGET_CMDS
	$(INSTALL) -m 755 -d $(TARGET_DIR)/etc
	$(INSTALL) -m 644 $(@D)/majestic-mini.yaml $(TARGET_DIR)/etc/majestic.yaml
	$(INSTALL) -m 644 $(@D)/majestic.yaml $(TARGET_DIR)/etc/majestic.full

	$(INSTALL) -m 755 -d $(TARGET_DIR)/usr/bin
	$(INSTALL) -m 755 -t $(TARGET_DIR)/usr/bin $(@D)/majestic
endef

$(eval $(generic-package))
