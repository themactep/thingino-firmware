COMPY_VERSION = 1459c0ad657798c061d7d30c60d42fe8148d054c
COMPY_SITE = https://github.com/gtxaspec/compy
COMPY_SITE_METHOD = git
COMPY_INSTALL_STAGING = YES
COMPY_INSTALL_TARGET = NO

COMPY_CONF_OPTS = \
	-DCOMPY_SHARED=OFF \
	-DCMAKE_C_FLAGS="$(TARGET_CFLAGS)"

# compy's CMakeLists.txt uses FetchContent for header-only macro
# libraries (slice99, datatype99, interface99, metalang99).
# These are fetched during the cmake configure step.

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
