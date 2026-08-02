################################################################################
#
# thingino-odhcp6c
#
################################################################################

THINGINO_ODHCP6C_VERSION = daf4ec3054e753c99fdcc3ac5464926548b38351
THINGINO_ODHCP6C_SITE = https://git.openwrt.org/project/odhcp6c.git
THINGINO_ODHCP6C_SITE_METHOD = git
THINGINO_ODHCP6C_LICENSE = GPL-2.0
THINGINO_ODHCP6C_LICENSE_FILES = COPYING
THINGINO_ODHCP6C_DEPENDENCIES = thingino-libubox

# State changes are applied by overlay/usr/lib/netifd/dhcpv6.script, the
# daemon's built-in default script path; no extra update script is needed.

$(eval $(cmake-package))
