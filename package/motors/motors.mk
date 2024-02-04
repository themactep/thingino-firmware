################################################################################
#
# motors
#
################################################################################

MOTORS_SITE_METHOD = git
MOTORS_SITE = https://github.com/openipc/motors.git
MOTORS_VERSION = $(shell git ls-remote $(MOTORS_SITE) HEAD | head -1 | cut -f1)

MOTORS_LICENSE = MIT
MOTORS_LICENSE_FILES = LICENSE

define MOTORS_BUILD_CMDS
	(cd $(@D)/ingenic-motor; $(TARGET_CC) -Os -s main.c -o ingenic-motor)
endef

define MOTORS_INSTALL_TARGET_CMDS
	$(INSTALL) -m 0755 -D $(@D)/ingenic-motor/ingenic-motor $(TARGET_DIR)/usr/bin/motors
endef

$(eval $(generic-package))
