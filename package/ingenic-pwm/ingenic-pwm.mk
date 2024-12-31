INGENIC_PWM_SITE_METHOD = git
INGENIC_PWM_SITE = https://github.com/gtxaspec/ingenic-pwm
INGENIC_PWM_SITE_BRANCH = master
INGENIC_PWM_VERSION = 8d45ebdb97600c7559f5b7eac8e42a9d8c38426b
# $(shell git ls-remote $(INGENIC_PWM_SITE) $(INGENIC_PWM_SITE_BRANCH) | head -1 | cut -f1)

define INGENIC_PWM_BUILD_CMDS
	$(MAKE) CROSS_COMPILE=$(TARGET_CROSS) LDFLAGS="$(TARGET_LDFLAGS)" -C $(@D)
endef

define INGENIC_PWM_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/ingenic-pwm $(TARGET_DIR)/usr/sbin/pwm
	$(INSTALL) -D -m 0755 $(INGENIC_PWM_PKGDIR)/files/pwm-ctrl $(TARGET_DIR)/usr/sbin/pwm-ctrl
endef

$(eval $(generic-package))
