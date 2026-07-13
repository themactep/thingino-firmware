################################################################################
#
# timps — Tiny IMP Streamer
#
################################################################################

TIMPS_SITE_METHOD = git
TIMPS_SITE = https://github.com/Lu-Fi/timps
TIMPS_VERSION = v1.2.0

# Submodule provides the IMP headers (ingenic-headers).
TIMPS_GIT_SUBMODULES = YES

TIMPS_DEPENDENCIES = ingenic-lib
ifeq ($(BR2_TOOLCHAIN_USES_MUSL),y)
	TIMPS_DEPENDENCIES += ingenic-musl
endif
ifeq ($(BR2_TOOLCHAIN_USES_UCLIBC),y)
	TIMPS_DEPENDENCIES += ingenic-uclibc
endif

ifeq ($(BR2_PACKAGE_TIMPS_FAAC),y)
	TIMPS_DEPENDENCIES += faac
endif

ifeq ($(BR2_PACKAGE_TIMPS_TLS),y)
	TIMPS_DEPENDENCIES += mbedtls
endif

ifeq ($(BR2_PACKAGE_TIMPS_SRT),y)
	TIMPS_DEPENDENCIES += libsrt
endif

# CFLAGS inherit TARGET_CFLAGS for arch-specific flags (critical for XBurst CPUs
# which need -mno-fused-madd / -ffp-contract=off). The timps Makefile adds its
# own -DUSE_* defines based on the USE_* variables we pass below, so we only
# add platform, kernel, and libc flags here.
TIMPS_CFLAGS = $(TARGET_CFLAGS) \
	-std=c11 -D_GNU_SOURCE -Os \
	-Wall -Wextra -Wno-unused-parameter -Wno-misleading-indentation \
	-Wno-stringop-truncation -ffunction-sections -fdata-sections

TIMPS_CFLAGS += -DPLATFORM_$(shell echo $(SOC_FAMILY) | tr a-z A-Z)
ifeq ($(KERNEL_VERSION),4.4.94)
	TIMPS_CFLAGS += -DKERNEL_VERSION_4
endif

ifeq ($(BR2_TOOLCHAIN_USES_GLIBC),y)
	TIMPS_CFLAGS += -DLIBC_GLIBC
endif
ifeq ($(BR2_TOOLCHAIN_USES_UCLIBC),y)
	TIMPS_CFLAGS += -DLIBC_UCLIBC
endif

# Buildroot staging has shared (.so) versions of the IMP libs, not static (.a).
# The upstream Makefile defaults to static: -l:libimp.a etc.
# We override to use the shared libraries installed by ingenic-lib.
TIMPS_IMPLIBS = -limp -lalog -lsysutils

# Additional system libs (extended from upstream -lpthread -lrt -lm)
TIMPS_LIBS = -lpthread -lrt -lm

ifeq ($(BR2_PACKAGE_TIMPS_TLS),y)
	TIMPS_LIBS += -lmbedtls -lmbedx509 -lmbedcrypto
endif

ifeq ($(BR2_PACKAGE_TIMPS_SRT),y)
	TIMPS_LIBS += -lsrt
endif

define TIMPS_BUILD_CMDS
	$(MAKE) \
		CROSS_COMPILE=$(TARGET_CROSS) \
		PLATFORM=$(shell echo $(SOC_FAMILY) | tr a-z A-Z) \
		IMP_LIB=$(STAGING_DIR)/usr/lib \
		IMPLIBS="$(TIMPS_IMPLIBS)" \
		CFLAGS="$(TIMPS_CFLAGS)" \
		LDFLAGS="$(TARGET_LDFLAGS) -Wl,--gc-sections -L$(STAGING_DIR)/usr/lib -L$(TARGET_DIR)/usr/lib" \
		LIBS="$(TIMPS_LIBS)" \
		USE_FAAC=$(if $(BR2_PACKAGE_TIMPS_FAAC),1,0) \
		USE_CONTROL=$(if $(BR2_PACKAGE_TIMPS_CONTROL),1,0) \
		USE_DAYNIGHT=$(if $(BR2_PACKAGE_TIMPS_DAYNIGHT),1,0) \
		USE_TLS=$(if $(BR2_PACKAGE_TIMPS_TLS),1,0) \
		USE_SRT=$(if $(BR2_PACKAGE_TIMPS_SRT),1,0) \
		-C $(@D) target
endef

define TIMPS_INSTALL_TARGET_CMDS
	# Install the streamer binary
	$(INSTALL) -D -m 0755 $(@D)/timpsd \
		$(TARGET_DIR)/usr/bin/timpsd

	# Copy to NFS share for dev iteration
	[ -d /nfs ] && cp $(TARGET_DIR)/usr/bin/timpsd /nfs/timpsd || true

	# Install default configuration file
	$(INSTALL) -D -m 0644 $(TIMPS_PKGDIR)/files/timps.conf \
		$(TARGET_DIR)/etc/timps.conf

	# Install init script
	$(INSTALL) -D -m 0755 $(TIMPS_PKGDIR)/files/S95timps \
		$(TARGET_DIR)/etc/init.d/S95timps

	# Install TLS certificate generation script if TLS is enabled
	if [ "$(BR2_PACKAGE_TIMPS_TLS)" = "y" ]; then \
		$(INSTALL) -D -m 0755 $(TIMPS_PKGDIR)/files/generate-tls-certs.sh \
			$(TARGET_DIR)/usr/bin/generate-timps-tls-certs.sh; \
	fi
endef

$(eval $(generic-package))
