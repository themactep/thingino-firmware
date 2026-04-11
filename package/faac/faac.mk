FAAC_SITE_METHOD = git
FAAC_SITE = https://github.com/knik0/faac
FAAC_SITE_BRANCH = master
FAAC_VERSION = 7ed850b7d2bc401814a36116839cc58bc475e58b

FAAC_LICENSE = MPEG-4-Reference-Code, LGPL-2.1+
FAAC_LICENSE_FILES = COPYING

FAAC_INSTALL_STAGING = YES
FAAC_INSTALL_TARGET = YES

FAAC_CFLAGS = $(TARGET_CFLAGS) -ffast-math -DHAVE_CONFIG_H \
	-I$(@D) -I$(@D)/include -fPIC

FAAC_LIBFAAC_SRCS = bitstream.c blockswitch.c channels.c cpu_compute.c \
	fft.c filtbank.c frame.c huff2.c huffdata.c \
	quantize.c stereo.c tns.c util.c

define FAAC_CONFIGURE_CMDS
	printf '%s\n' \
		'#define PACKAGE "faac"' \
		'#define PACKAGE_VERSION "1.40.0"' \
		'#define HAVE_GETOPT_H 1' \
		'#define HAVE_STDINT_H 1' \
		'#define HAVE_SYS_TIME_H 1' \
		'#define HAVE_SYS_TYPES_H 1' \
		'#define HAVE_STRCASECMP 1' \
		'#define FAAC_PRECISION_SINGLE 1' \
		'#define MAX_CHANNELS 2' \
		> $(@D)/config.h
endef

define FAAC_BUILD_CMDS
	for f in $(FAAC_LIBFAAC_SRCS); do \
		$(TARGET_CC) $(FAAC_CFLAGS) -c \
			$(@D)/libfaac/$$f -o $(@D)/libfaac/$${f%.c}.o || exit 1; \
	done
	$(TARGET_AR) rcs $(@D)/libfaac/libfaac.a \
		$(addprefix $(@D)/libfaac/,$(FAAC_LIBFAAC_SRCS:.c=.o))
	$(TARGET_CC) -shared -Wl,-soname,libfaac.so \
		$(addprefix $(@D)/libfaac/,$(FAAC_LIBFAAC_SRCS:.c=.o)) \
		$(TARGET_LDFLAGS) -lm -o $(@D)/libfaac/libfaac.so
	$(FAAC_BUILD_FRONTEND)
endef

define FAAC_INSTALL_STAGING_CMDS
	$(INSTALL) -D -m 0644 $(@D)/include/faac.h $(STAGING_DIR)/usr/include/faac.h
	$(INSTALL) -D -m 0644 $(@D)/include/faaccfg.h $(STAGING_DIR)/usr/include/faaccfg.h
	$(INSTALL) -D -m 0644 $(@D)/libfaac/libfaac.a $(STAGING_DIR)/usr/lib/libfaac.a
	$(INSTALL) -D -m 0755 $(@D)/libfaac/libfaac.so $(STAGING_DIR)/usr/lib/libfaac.so
	mkdir -p $(STAGING_DIR)/usr/lib/pkgconfig
	sed -e 's|@prefix@|/usr|' \
		-e 's|@exec_prefix@|/usr|' \
		-e 's|@libdir@|/usr/lib|' \
		-e 's|@includedir@|/usr/include|' \
		-e 's|@VERSION@|1.40.0|' \
		$(@D)/libfaac/faac.pc.in > $(STAGING_DIR)/usr/lib/pkgconfig/faac.pc
endef

define FAAC_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/libfaac/libfaac.so $(TARGET_DIR)/usr/lib/libfaac.so
endef

ifeq ($(BR2_PACKAGE_FAAC_INSTALL_BIN),y)
define FAAC_BUILD_FRONTEND
	$(TARGET_CC) $(FAAC_CFLAGS) $(TARGET_LDFLAGS) \
		$(@D)/frontend/main.c $(@D)/frontend/input.c $(@D)/frontend/mp4write.c \
		-I$(@D)/frontend -L$(@D)/libfaac -lfaac -lm \
		-o $(@D)/frontend/faac
endef

define FAAC_INSTALL_FRONTEND_TARGET
	$(INSTALL) -D -m 0755 $(@D)/frontend/faac $(TARGET_DIR)/usr/bin/faac
endef
FAAC_POST_INSTALL_TARGET_HOOKS += FAAC_INSTALL_FRONTEND_TARGET
endif

$(eval $(generic-package))
