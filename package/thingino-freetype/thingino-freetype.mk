THINGINO_FREETYPE_VERSION = 2.14.1
THINGINO_FREETYPE_SOURCE = freetype-$(THINGINO_FREETYPE_VERSION).tar.xz
THINGINO_FREETYPE_SITE = http://download.savannah.gnu.org/releases/freetype
THINGINO_FREETYPE_INSTALL_STAGING = YES
THINGINO_FREETYPE_MAKE_OPTS = CCexe="$(HOSTCC)"
THINGINO_FREETYPE_LICENSE = FTL or GPL-2.0+
THINGINO_FREETYPE_LICENSE_FILES = LICENSE.TXT docs/FTL.TXT docs/GPLv2.TXT
THINGINO_FREETYPE_CPE_ID_VENDOR = freetype
THINGINO_FREETYPE_DEPENDENCIES = host-pkgconf
THINGINO_FREETYPE_CONFIG_SCRIPTS = freetype-config

# harfbuzz already depends on freetype so disable harfbuzz in freetype to avoid
# a circular dependency
THINGINO_FREETYPE_CONF_OPTS = \
	--without-harfbuzz \
	--disable-largefile \
	--disable-mmap \
	--without-png \
	--without-brotli \
	--without-zlib

HOST_THINGINO_FREETYPE_DEPENDENCIES = host-pkgconf
HOST_THINGINO_FREETYPE_CONF_OPTS = \
	--without-brotli \
	--without-bzip2 \
	--without-harfbuzz \
	--without-png \
	--without-zlib

# since 2.9.1 needed for freetype-config install
THINGINO_FREETYPE_CONF_OPTS += --enable-freetype-config
HOST_THINGINO_FREETYPE_CONF_OPTS += --enable-freetype-config

ifeq ($(BR2_PACKAGE_ZLIB),y)
THINGINO_FREETYPE_DEPENDENCIES += zlib
THINGINO_FREETYPE_CONF_OPTS += --with-zlib
else
THINGINO_FREETYPE_CONF_OPTS += --without-zlib
endif

ifeq ($(BR2_PACKAGE_BROTLI),y)
THINGINO_FREETYPE_DEPENDENCIES += brotli
THINGINO_FREETYPE_CONF_OPTS += --with-brotli
else
THINGINO_FREETYPE_CONF_OPTS += --without-brotli
endif

ifeq ($(BR2_PACKAGE_BZIP2),y)
THINGINO_FREETYPE_DEPENDENCIES += bzip2
THINGINO_FREETYPE_CONF_OPTS += --with-bzip2
else
THINGINO_FREETYPE_CONF_OPTS += --without-bzip2
endif

ifeq ($(BR2_PACKAGE_LIBPNG),y)
THINGINO_FREETYPE_DEPENDENCIES += libpng
THINGINO_FREETYPE_CONF_OPTS += --with-png
else
THINGINO_FREETYPE_CONF_OPTS += --without-png
endif

# Extra fixing since includedir and libdir are expanded from configure values
define THINGINO_FREETYPE_FIX_CONFIG_FILE
	$(SED) 's:^includedir=.*:includedir="$${prefix}/include":' \
		-e 's:^libdir=.*:libdir="$${exec_prefix}/lib":' \
		$(STAGING_DIR)/usr/bin/freetype-config
endef
THINGINO_FREETYPE_POST_INSTALL_STAGING_HOOKS += THINGINO_FREETYPE_FIX_CONFIG_FILE

$(eval $(autotools-package))
$(eval $(host-autotools-package))
