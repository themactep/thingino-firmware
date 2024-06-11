INGENIC_PWM_SITE_METHOD = git
INGENIC_PWM_SITE = https://github.com/gtxaspec/ingenic-pwm
INGENIC_PWM_SITE_BRANCH = master
INGENIC_PWM_VERSION = $(shell git ls-remote $(INGENIC_PWM_SITE) $(INGENIC_PWM_SITE_BRANCH) | head -1 | cut -f1)

define INGENIC_PWM_BUILD_CMDS
	$(MAKE) CROSS_COMPILE=$(TARGET_CROSS) -C $(@D)
endef

define INGENIC_PWM_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/ingenic-pwm $(TARGET_DIR)/usr/bin/pwm
endef

$(eval $(generic-package))
