################################################################################
#
# libpeer
#
################################################################################

LIBPEER_SITE = https://github.com/themactep/libpeer
LIBPEER_SITE_BRANCH = thingino-mbedtls-3.6
LIBPEER_VERSION = $(shell git ls-remote $(LIBPEER_SITE) $(LIBPEER_SITE_BRANCH) | head -1 | cut -f1)
LIBPEER_SITE_METHOD = git
LIBPEER_GIT_SUBMODULES = YES
LIBPEER_LICENSE = MIT
LIBPEER_LICENSE_FILES = LICENSE
LIBPEER_INSTALL_STAGING = YES
LIBPEER_INSTALL_TARGET = YES

# Dependencies - thingino-libpeer fork uses system libraries
LIBPEER_DEPENDENCIES = libsrtp
ifeq ($(BR2_PACKAGE_MBEDTLS),y)
LIBPEER_DEPENDENCIES += mbedtls
endif

# Simple CMake configuration for clean fork
LIBPEER_CONF_OPTS = \
	-DCMAKE_BUILD_TYPE=Release \
	-DBUILD_SHARED_LIBS=ON

# SCTP support disabled - usrsctp not available in thingino

# Patch applied automatically by buildroot: 0001-use-system-mbedtls.patch

# Post-install hook to create pkg-config file
define LIBPEER_INSTALL_PKGCONFIG
	mkdir -p $(STAGING_DIR)/usr/lib/pkgconfig
	echo "prefix=$(STAGING_DIR)/usr" > $(STAGING_DIR)/usr/lib/pkgconfig/libpeer.pc
	echo "exec_prefix=\$${prefix}" >> $(STAGING_DIR)/usr/lib/pkgconfig/libpeer.pc
	echo "libdir=\$${exec_prefix}/lib" >> $(STAGING_DIR)/usr/lib/pkgconfig/libpeer.pc
	echo "includedir=\$${prefix}/include" >> $(STAGING_DIR)/usr/lib/pkgconfig/libpeer.pc
	echo "" >> $(STAGING_DIR)/usr/lib/pkgconfig/libpeer.pc
	echo "Name: libpeer" >> $(STAGING_DIR)/usr/lib/pkgconfig/libpeer.pc
	echo "Description: Lightweight WebRTC library for embedded systems" >> $(STAGING_DIR)/usr/lib/pkgconfig/libpeer.pc
	echo "Version: $(LIBPEER_VERSION)" >> $(STAGING_DIR)/usr/lib/pkgconfig/libpeer.pc
	echo "Requires: mbedtls libsrtp2" >> $(STAGING_DIR)/usr/lib/pkgconfig/libpeer.pc
	echo "Libs: -L\$${libdir} -lpeer" >> $(STAGING_DIR)/usr/lib/pkgconfig/libpeer.pc
	echo "Cflags: -I\$${includedir}" >> $(STAGING_DIR)/usr/lib/pkgconfig/libpeer.pc
endef

LIBPEER_POST_INSTALL_STAGING_HOOKS += LIBPEER_INSTALL_PKGCONFIG

# Install development headers
define LIBPEER_INSTALL_HEADERS
	mkdir -p $(STAGING_DIR)/usr/include
	if [ -d "$(@D)/include" ]; then \
		cp -r $(@D)/include/* $(STAGING_DIR)/usr/include/; \
	fi
	if [ -d "$(@D)/src" ]; then \
		find $(@D)/src -name "*.h" -exec cp {} $(STAGING_DIR)/usr/include/ \; ; \
	fi
endef

LIBPEER_POST_INSTALL_STAGING_HOOKS += LIBPEER_INSTALL_HEADERS

# Install runtime library to target
define LIBPEER_INSTALL_TARGET_LIBS
	$(INSTALL) -D -m 0755 $(STAGING_DIR)/usr/lib/libpeer.so* $(TARGET_DIR)/usr/lib/
endef

LIBPEER_POST_INSTALL_TARGET_HOOKS += LIBPEER_INSTALL_TARGET_LIBS

# thingino-libpeer fork - clean implementation without patches

$(eval $(cmake-package))
