################################################################################
#
# thingino-libubox
#
################################################################################

THINGINO_LIBUBOX_VERSION = 815633847cd32ffe6da28943cbeb37edc88265c8
THINGINO_LIBUBOX_SITE = https://git.openwrt.org/project/libubox.git
THINGINO_LIBUBOX_SITE_METHOD = git
THINGINO_LIBUBOX_LICENSE = ISC, BSD-3-Clause
THINGINO_LIBUBOX_INSTALL_STAGING = YES
THINGINO_LIBUBOX_DEPENDENCIES = thingino-jct

ifeq ($(BR2_USE_MMU)$(BR2_PACKAGE_LUA_5_1),yy)
THINGINO_LIBUBOX_DEPENDENCIES += lua
THINGINO_LIBUBOX_CONF_OPTS += -DBUILD_LUA=ON \
	-DLUAPATH=/usr/lib/lua/5.1 \
	-DLUA_CFLAGS=-I$(STAGING_DIR)/usr/include
else
THINGINO_LIBUBOX_CONF_OPTS += -DBUILD_LUA=OFF
endif

$(eval $(cmake-package))
