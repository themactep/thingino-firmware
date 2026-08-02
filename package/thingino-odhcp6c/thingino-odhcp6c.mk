################################################################################
#
# thingino-odhcp6c
#
################################################################################

THINGINO_ODHCP6C_VERSION = 10a52220aec9d45803518d8cc4d63e552484ed61
THINGINO_ODHCP6C_SITE = https://git.openwrt.org/project/odhcp6c.git
THINGINO_ODHCP6C_SITE_METHOD = git
THINGINO_ODHCP6C_LICENSE = GPL-2.0
THINGINO_ODHCP6C_LICENSE_FILES = COPYING
THINGINO_ODHCP6C_DEPENDENCIES = thingino-libubox

# State changes are applied by overlay/usr/lib/netifd/dhcpv6.script, the
# daemon's built-in default script path; no extra update script is needed.

$(eval $(cmake-package))
