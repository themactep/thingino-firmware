THINGINO_IMP_TEST_SITE_METHOD = local
THINGINO_IMP_TEST_SITE = $(THINGINO_IMP_TEST_PKGDIR)

THINGINO_IMP_TEST_DEPENDENCIES += ingenic-lib

ifeq ($(BR2_PACKAGE_FAAC),y)
	THINGINO_IMP_TEST_DEPENDENCIES += faac
	THINGINO_IMP_TEST_BUILD_FAAC = yes
endif

ifeq ($(BR2_TOOLCHAIN_USES_MUSL),y)
	THINGINO_IMP_TEST_DEPENDENCIES += ingenic-musl
	THINGINO_IMP_TEST_SHIM = -lmuslshim
endif

ifeq ($(BR2_TOOLCHAIN_USES_UCLIBC),y)
	THINGINO_IMP_TEST_DEPENDENCIES += ingenic-uclibc
	THINGINO_IMP_TEST_SHIM = -luclibcshim
endif

define THINGINO_IMP_TEST_BUILD_CMDS
	$(TARGET_CC) $(TARGET_CFLAGS) -Wall -Wextra -o $(@D)/imp-test-audio \
		$(@D)/imp-test-audio.c \
		$(TARGET_LDFLAGS) \
		-L$(STAGING_DIR)/usr/lib \
		-L$(TARGET_DIR)/usr/lib \
		-limp -lalog -laudioProcess \
		-Wl,--no-as-needed $(THINGINO_IMP_TEST_SHIM) -Wl,--as-needed \
		-lrt -lpthread
	if [ "$(THINGINO_IMP_TEST_BUILD_FAAC)" = "yes" ]; then \
		$(TARGET_CC) $(TARGET_CFLAGS) -Wall -Wextra \
			-I$(STAGING_DIR)/usr/include \
			-o $(@D)/imp-test-faac \
			$(@D)/imp-test-faac.c \
			$(TARGET_LDFLAGS) \
			-L$(STAGING_DIR)/usr/lib \
			-lfaac -lm; \
	fi
endef

define THINGINO_IMP_TEST_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/imp-test-audio \
		$(TARGET_DIR)/usr/bin/imp-test-audio
	if [ -f $(@D)/imp-test-faac ]; then \
		$(INSTALL) -D -m 0755 $(@D)/imp-test-faac \
			$(TARGET_DIR)/usr/bin/imp-test-faac; \
	fi
endef

$(eval $(generic-package))
