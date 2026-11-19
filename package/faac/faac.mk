FAAC_VERSION = 3.0
FAAC_SITE = $(call github,FreewareAdvancedAudio,faac,faac-$(FAAC_VERSION))

FAAC_LICENSE = LGPL-2.1+
FAAC_LICENSE_FILES = COPYING

FAAC_INSTALL_STAGING = YES
FAAC_INSTALL_TARGET = YES

# Inline sqrtf() in the quantizer instead of calling libm for each one; the
# encoder's output is unchanged. Not -ffast-math: it implies
# -ffinite-math-only, and faac relies on isfinite() and isnan().
FAAC_CFLAGS = $(TARGET_CFLAGS) -fno-math-errno

FAAC_CONF_OPTS = \
	-Dmax-channels=2 \
	-Ddecoder=false \
	-Dmuxer=false \
	-Dresampler=false

ifeq ($(BR2_PACKAGE_FAAC_INSTALL_BIN),y)
FAAC_CONF_OPTS += -Dfrontend=true
else
FAAC_CONF_OPTS += -Dfrontend=false
endif

ifeq ($(BR2_PACKAGE_FAAC_INSTALL_BIN),)
# libfaam and libfaar are always built, but nothing in the firmware uses them
# when the CLI is not installed.
define FAAC_REMOVE_UNUSED_LIBS
	rm -f $(TARGET_DIR)/usr/lib/libfaam.* $(TARGET_DIR)/usr/lib/libfaar.*
	rm -f $(STAGING_DIR)/usr/lib/libfaam.* $(STAGING_DIR)/usr/lib/libfaar.*
endef
FAAC_POST_INSTALL_STAGING_HOOKS += FAAC_REMOVE_UNUSED_LIBS
FAAC_POST_INSTALL_TARGET_HOOKS += FAAC_REMOVE_UNUSED_LIBS
endif

$(eval $(meson-package))
