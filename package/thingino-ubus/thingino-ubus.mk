################################################################################
#
# thingino-ubus
#
################################################################################

THINGINO_UBUS_VERSION = 3cc98db1a422dcf560f2d6347fd410f17565a89d
THINGINO_UBUS_SITE = https://git.openwrt.org/project/ubus.git
THINGINO_UBUS_SITE_METHOD = git

THINGINO_UBUS_LICENSE = LGPL-2.1
THINGINO_UBUS_LICENSE_FILES = ubusd_acl.h

THINGINO_UBUS_INSTALL_STAGING = YES

THINGINO_UBUS_DEPENDENCIES = thingino-jct thingino-libubox

ifeq ($(BR2_PACKAGE_LUA_5_1),y)
THINGINO_UBUS_DEPENDENCIES += lua
THINGINO_UBUS_CONF_OPTS += -DBUILD_LUA=ON \
	-DLUA_CFLAGS=-I$(STAGING_DIR)/usr/include \
	-DLUAPATH=/usr/lib/lua/$(LUAINTERPRETER_ABIVER)
else
THINGINO_UBUS_CONF_OPTS += -DBUILD_LUA=OFF
endif

ifeq ($(BR2_PACKAGE_THINGINO_UBUS_EXAMPLES),y)
THINGINO_UBUS_CONF_OPTS += -DBUILD_EXAMPLES=ON
else
THINGINO_UBUS_CONF_OPTS += -DBUILD_EXAMPLES=OFF
endif

$(eval $(cmake-package))
