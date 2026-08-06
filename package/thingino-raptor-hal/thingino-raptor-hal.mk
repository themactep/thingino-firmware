THINGINO_RAPTOR_HAL_VERSION = 3b6b83d70c2d1cc1367ce8e0a1476ae92fc6e053
THINGINO_RAPTOR_HAL_SITE = https://github.com/matteius/raptor-hal
THINGINO_RAPTOR_HAL_SITE_METHOD = git
THINGINO_RAPTOR_HAL_GIT_SUBMODULES = YES
THINGINO_RAPTOR_HAL_INSTALL_STAGING = YES
THINGINO_RAPTOR_HAL_INSTALL_TARGET = NO

THINGINO_RAPTOR_HAL_DEPENDENCIES = ingenic-lib

THINGINO_RAPTOR_HAL_PLATFORM = $(shell echo $(SOC_FAMILY) | tr a-z A-Z)

define THINGINO_RAPTOR_HAL_BUILD_CMDS
	$(MAKE) -C $(@D) \
		PLATFORM=$(THINGINO_RAPTOR_HAL_PLATFORM) \
		CROSS_COMPILE=$(TARGET_CROSS) \
		INGENIC_HEADERS=$(@D)/ingenic-headers \
		$(if $(BR2_PACKAGE_THINGINO_RAPTOR_IVS_DETECT),\
			CXX=$(TARGET_CROSS)g++ \
			JZDL_INCLUDE=$(@D)/ingenic-headers/Txx/jzdl,) \
		$(if $(BR2_PACKAGE_THINGINO_RAPTOR_IVS_PERSONDET),PERSONDET=1,) \
		$(if $(BR2_PACKAGE_THINGINO_RAPTOR_DEBUG),DEBUG=1,)
endef

define THINGINO_RAPTOR_HAL_INSTALL_STAGING_CMDS
	$(INSTALL) -D -m 0644 $(@D)/libraptor_hal_video.a \
		$(STAGING_DIR)/usr/lib/libraptor_hal_video.a
	$(INSTALL) -D -m 0644 $(@D)/libraptor_hal_audio.a \
		$(STAGING_DIR)/usr/lib/libraptor_hal_audio.a
	$(INSTALL) -D -m 0644 $(@D)/include/raptor_hal.h \
		$(STAGING_DIR)/usr/include/raptor_hal.h
endef

$(eval $(generic-package))
