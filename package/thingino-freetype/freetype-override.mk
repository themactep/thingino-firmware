################################################################################
#
# freetype overrides for Thingino
#
################################################################################

ifeq ($(BR2_PACKAGE_THINGINO_FREETYPE),y)

override FREETYPE_VERSION = 2.14.1
override FREETYPE_SOURCE = freetype-$(FREETYPE_VERSION).tar.xz
override FREETYPE_SITE = http://download.savannah.gnu.org/releases/freetype

# Append legacy flags only after Buildroot's freetype.mk has set defaults.
# These --disable-largefile and --disable-mmap flags keep Thingino’s freetype build
# identical to the one in Ingenic’s 1.1.6 SDK that our released images are based on.
# That legacy toolchain (uclibc, GCC 5.4) shipped freetype with large-file and mmap
# support explicitly disabled, so packages linking against it were built and tested
# assuming 32‑bit file offsets and the older stdio APIs. Re-enabling large-file or mmap
# in our override would change the exported ABI (e.g. structure sizes, feature macros)
# and can trigger subtle regressions in closed-source blobs or prebuilt libs that still
# ship alongside the firmware. So we keep --disable-largefile --disable-mmap to guarantee
# binary compatibility and reproducible hashes with the existing camera fleet until we
# do a full SDK/toolchain realignment.
ifneq ($(origin FREETYPE_CONF_OPTS),undefined)
ifeq ($(filter --disable-largefile,$(FREETYPE_CONF_OPTS)),)
FREETYPE_CONF_OPTS += --disable-largefile --disable-mmap
endif
endif

override define FREETYPE_FIX_CONFIG_FILE
	@if [ -f $(STAGING_DIR)/usr/bin/freetype-config ]; then \
		$(SED) 's:^includedir=.*:includedir="$$$${prefix}/include":' \
			-e 's:^libdir=.*:libdir="$$$${exec_prefix}/lib":' \
			$(STAGING_DIR)/usr/bin/freetype-config; \
	fi
endef

endif
