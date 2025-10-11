# We use older version that does not mandate NUMA
THINGINO_RT_TESTS_VERSION = v0.86
THINGINO_RT_TESTS_SITE = https://git.kernel.org/pub/scm/utils/rt-tests/rt-tests.git
THINGINO_RT_TESTS_SITE_METHOD = git
THINGINO_RT_TESTS_LICENSE = GPL-2.0
THINGINO_RT_TESTS_LICENSE_FILES = COPYING

# Dependencies
THINGINO_RT_TESTS_DEPENDENCIES = host-pkgconf

# Optional NUMA support for targets that have it
ifeq ($(BR2_PACKAGE_NUMACTL),y)
THINGINO_RT_TESTS_DEPENDENCIES += numactl
THINGINO_RT_TESTS_NUMA = 1
else
THINGINO_RT_TESTS_NUMA = 0
endif

# Build all rt-tests programs
define THINGINO_RT_TESTS_BUILD_CMDS
	$(TARGET_MAKE_ENV) $(MAKE) -C $(@D) \
		NUMA=$(THINGINO_RT_TESTS_NUMA) \
		CROSS_COMPILE="$(TARGET_CROSS)" \
		CC="$(TARGET_CC)" \
		AR="$(TARGET_AR)" \
		CFLAGS="$(TARGET_CFLAGS)" \
		LDFLAGS="$(TARGET_LDFLAGS)" \
		all
endef

# Install only essential binary programs (minimal embedded footprint)
define THINGINO_RT_TESTS_INSTALL_TARGET_CMDS
	# Install only the compiled binary programs - no documentation
	$(INSTALL) -D -m 0755 $(@D)/cyclictest $(TARGET_DIR)/usr/bin/cyclictest
	$(INSTALL) -D -m 0755 $(@D)/signaltest $(TARGET_DIR)/usr/bin/signaltest
	$(INSTALL) -D -m 0755 $(@D)/pi_stress $(TARGET_DIR)/usr/bin/pi_stress
	$(INSTALL) -D -m 0755 $(@D)/rt-migrate-test $(TARGET_DIR)/usr/bin/rt-migrate-test
	$(INSTALL) -D -m 0755 $(@D)/ptsematest $(TARGET_DIR)/usr/bin/ptsematest
	$(INSTALL) -D -m 0755 $(@D)/sigwaittest $(TARGET_DIR)/usr/bin/sigwaittest
	$(INSTALL) -D -m 0755 $(@D)/svsematest $(TARGET_DIR)/usr/bin/svsematest
	$(INSTALL) -D -m 0755 $(@D)/pmqtest $(TARGET_DIR)/usr/bin/pmqtest
	$(INSTALL) -D -m 0755 $(@D)/sendme $(TARGET_DIR)/usr/bin/sendme
	$(INSTALL) -D -m 0755 $(@D)/pip_stress $(TARGET_DIR)/usr/bin/pip_stress
	$(INSTALL) -D -m 0755 $(@D)/hackbench $(TARGET_DIR)/usr/bin/hackbench
endef

# Install init script for cyclictest service (optional)
ifeq ($(BR2_PACKAGE_THINGINO_RT_TESTS_INIT_SCRIPT),y)
define THINGINO_RT_TESTS_INSTALL_INIT_SYSV
	$(INSTALL) -D -m 0755 $(THINGINO_RT_TESTS_PKGDIR)/S99cyclictest \
		$(TARGET_DIR)/etc/init.d/S99cyclictest
	$(INSTALL) -D -m 0755 $(THINGINO_RT_TESTS_PKGDIR)/runandreportcyclictest \
		$(TARGET_DIR)/usr/bin/runandreportcyclictest
endef
endif

$(eval $(generic-package))
