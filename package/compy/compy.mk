COMPY_VERSION = 55797ad685e651825c60d50a8038a0ce9e1f910d
COMPY_SITE = https://github.com/gtxaspec/compy
COMPY_SITE_METHOD = git
COMPY_INSTALL_STAGING = YES
COMPY_INSTALL_TARGET = NO

COMPY_CONF_OPTS = \
	-DCOMPY_SHARED=OFF \
	-DCMAKE_C_FLAGS="$(TARGET_CFLAGS)" \
	-DCMAKE_AR=$(TARGET_CROSS)gcc-ar \
	-DCMAKE_RANLIB=$(TARGET_CROSS)gcc-ranlib

ifeq ($(BR2_PACKAGE_MBEDTLS),y)
COMPY_CONF_OPTS += -DCOMPY_TLS_MBEDTLS=ON
COMPY_DEPENDENCIES += mbedtls
endif

# compy's CMakeLists.txt uses FetchContent to pull in four header-only
# macro libraries: slice99, datatype99, interface99, and (nested, from
# datatype99/interface99) metalang99. Fetching them during the cmake
# configure step bypasses the Buildroot download cache, so a clean build
# fails whenever GitHub is unreachable or rate-limits us (HTTP 429).
# Declare them as extra downloads instead, so they are fetched once into
# the download cache and hash-checked like any other source, and point
# FetchContent at the pre-extracted directories via
# FETCHCONTENT_SOURCE_DIR_<NAME> so configure never touches the network.
COMPY_SLICE99_VERSION = 0.7.8
COMPY_DATATYPE99_VERSION = 1.6.5
COMPY_INTERFACE99_VERSION = 1.0.2
COMPY_METALANG99_VERSION = 1.13.5

COMPY_EXTRA_DOWNLOADS = \
	https://github.com/Hirrolot/slice99/archive/refs/tags/v$(COMPY_SLICE99_VERSION)/slice99-v$(COMPY_SLICE99_VERSION).tar.gz \
	https://github.com/Hirrolot/datatype99/archive/refs/tags/v$(COMPY_DATATYPE99_VERSION)/datatype99-v$(COMPY_DATATYPE99_VERSION).tar.gz \
	https://github.com/Hirrolot/interface99/archive/refs/tags/v$(COMPY_INTERFACE99_VERSION)/interface99-v$(COMPY_INTERFACE99_VERSION).tar.gz \
	https://github.com/Hirrolot/metalang99/archive/refs/tags/v$(COMPY_METALANG99_VERSION)/metalang99-v$(COMPY_METALANG99_VERSION).tar.gz

# The compy sources themselves come from git, so they have no stable
# hash; the hashes in compy.hash only cover the extra downloads above.
BR_NO_CHECK_HASH_FOR += $(COMPY_SOURCE)

COMPY_CONF_OPTS += \
	-DFETCHCONTENT_SOURCE_DIR_SLICE99=$(@D)/_deps/slice99-src \
	-DFETCHCONTENT_SOURCE_DIR_DATATYPE99=$(@D)/_deps/datatype99-src \
	-DFETCHCONTENT_SOURCE_DIR_INTERFACE99=$(@D)/_deps/interface99-src \
	-DFETCHCONTENT_SOURCE_DIR_METALANG99=$(@D)/_deps/metalang99-src

# Populate the _deps/<name>-src directories FetchContent would have
# created, so the install commands below keep working unchanged.
define COMPY_SETUP_FETCHCONTENT_SOURCES
	mkdir -p $(@D)/_deps/slice99-src $(@D)/_deps/datatype99-src \
		$(@D)/_deps/interface99-src $(@D)/_deps/metalang99-src
	$(TAR) --strip-components=1 -C $(@D)/_deps/slice99-src \
		-xf $(COMPY_DL_DIR)/slice99-v$(COMPY_SLICE99_VERSION).tar.gz
	$(TAR) --strip-components=1 -C $(@D)/_deps/datatype99-src \
		-xf $(COMPY_DL_DIR)/datatype99-v$(COMPY_DATATYPE99_VERSION).tar.gz
	$(TAR) --strip-components=1 -C $(@D)/_deps/interface99-src \
		-xf $(COMPY_DL_DIR)/interface99-v$(COMPY_INTERFACE99_VERSION).tar.gz
	$(TAR) --strip-components=1 -C $(@D)/_deps/metalang99-src \
		-xf $(COMPY_DL_DIR)/metalang99-v$(COMPY_METALANG99_VERSION).tar.gz
endef
COMPY_POST_EXTRACT_HOOKS += COMPY_SETUP_FETCHCONTENT_SOURCES

# No install() rules in upstream CMakeLists.txt, so install manually.
define COMPY_INSTALL_STAGING_CMDS
	$(INSTALL) -D -m 0644 $(@D)/libcompy.a \
		$(STAGING_DIR)/usr/lib/libcompy.a
	mkdir -p $(STAGING_DIR)/usr/include
	cp -f $(@D)/include/compy.h $(STAGING_DIR)/usr/include/
	cp -a $(@D)/include/compy $(STAGING_DIR)/usr/include/
	# Header-only transitive dependencies (from FetchContent)
	cp -f $(@D)/_deps/slice99-src/slice99.h \
		$(STAGING_DIR)/usr/include/
	cp -f $(@D)/_deps/datatype99-src/datatype99.h \
		$(STAGING_DIR)/usr/include/
	cp -f $(@D)/_deps/interface99-src/interface99.h \
		$(STAGING_DIR)/usr/include/
	cp -f $(@D)/_deps/metalang99-src/include/metalang99.h \
		$(STAGING_DIR)/usr/include/
	cp -a $(@D)/_deps/metalang99-src/include/metalang99 \
		$(STAGING_DIR)/usr/include/
endef

$(eval $(cmake-package))
