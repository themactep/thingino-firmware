################################################################################
#
# thingino-libubox
#
################################################################################

THINGINO_LIBUBOX_VERSION = da2d205a5cf3e877c45a2eec488218cbaf452e7d
THINGINO_LIBUBOX_SITE = https://git.openwrt.org/project/libubox.git
THINGINO_LIBUBOX_SITE_METHOD = git
THINGINO_LIBUBOX_SITE_BRANCH = master
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
