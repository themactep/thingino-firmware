################################################################################
#
# live555 overrides for Thingino
#
################################################################################

ifeq ($(BR2_PACKAGE_THINGINO_LIVE555),y)

# Pin to a specific version tested with Thingino
override LIVE555_VERSION = 2025.10.13
override LIVE555_SITE = https://download.videolan.org/contrib/live555

# Override CFLAGS to remove -std=c++20 from being passed to C files
override LIVE555_CFLAGS = $(TARGET_CFLAGS)
# Build both static and shared libraries for flexibility
override LIVE555_CONFIG_TARGET = linux-with-shared-libraries
override LIVE555_LIBRARY_LINK = $(TARGET_CC) -o
override LIVE555_CFLAGS += -fPIC

ifeq ($(BR2_PACKAGE_OPENSSL),y)
override LIVE555_DEPENDENCIES += host-pkgconf openssl
override LIVE555_CONSOLE_LIBS = `$(PKG_CONFIG_HOST_BINARY) --libs openssl`
ifneq ($(BR2_STATIC_LIBS),y)
override LIVE555_LIVEMEDIA_LIBS = $(LIVE555_CONSOLE_LIBS)
endif
else
override LIVE555_CFLAGS += -DNO_OPENSSL
endif

ifneq ($(BR2_ENABLE_LOCALE),y)
override LIVE555_CFLAGS += -DLOCALE_NOT_USED
endif

# For GCC 11+, add C++ standard flag separately for C++ files only
ifeq ($(BR2_TOOLCHAIN_GCC_AT_LEAST_11),y)
override LIVE555_CPLUSPLUS_FLAGS = -std=c++20
else
override LIVE555_CFLAGS += -DNO_STD_LIB=1
endif

# Override configure to set C and C++ flags separately
override define LIVE555_CONFIGURE_CMDS
	echo 'COMPILE_OPTS = $$(INCLUDES) -I. -DSOCKLEN_T=socklen_t $(LIVE555_CFLAGS)' >> $(@D)/config.$(LIVE555_CONFIG_TARGET)
	echo 'C_FLAGS = $$(COMPILE_OPTS) $$(CPPFLAGS) $$(CFLAGS)' >> $(@D)/config.$(LIVE555_CONFIG_TARGET)
	echo 'CPLUSPLUS_FLAGS = $$(COMPILE_OPTS) -Wall -DBSD=1 $(LIVE555_CPLUSPLUS_FLAGS) $$(CPPFLAGS) $$(CXXFLAGS)' >> $(@D)/config.$(LIVE555_CONFIG_TARGET)
	echo 'C_COMPILER = $(TARGET_CC)' >> $(@D)/config.$(LIVE555_CONFIG_TARGET)
	echo 'CPLUSPLUS_COMPILER = $(TARGET_CXX)' >> $(@D)/config.$(LIVE555_CONFIG_TARGET)
	echo 'LINK = $(TARGET_CXX) -o' >> $(@D)/config.$(LIVE555_CONFIG_TARGET)
	echo 'LINK_OPTS = -L. $(TARGET_LDFLAGS)' >> $(@D)/config.$(LIVE555_CONFIG_TARGET)
	echo 'PREFIX = /usr' >> $(@D)/config.$(LIVE555_CONFIG_TARGET)
	echo 'LIBRARY_LINK = $(LIVE555_LIBRARY_LINK) ' >> $(@D)/config.$(LIVE555_CONFIG_TARGET)
	echo 'LIBS_FOR_CONSOLE_APPLICATION = $(LIVE555_CONSOLE_LIBS)' >> $(@D)/config.$(LIVE555_CONFIG_TARGET)
	echo 'LIBS_FOR_LIVEMEDIA_LIB = $(LIVE555_LIVEMEDIA_LIBS)' >> $(@D)/config.$(LIVE555_CONFIG_TARGET)
	(cd $(@D); ./genMakefiles $(LIVE555_CONFIG_TARGET))
endef

# Skip building test programs and media servers - we only need the libraries
# Build shared libraries always, static libraries only if needed
override define LIVE555_BUILD_CMDS
	$(TARGET_MAKE_ENV) $(MAKE) -C $(@D)/groupsock
	$(TARGET_MAKE_ENV) $(MAKE) -C $(@D)/liveMedia
	$(TARGET_MAKE_ENV) $(MAKE) -C $(@D)/UsageEnvironment
	$(TARGET_MAKE_ENV) $(MAKE) -C $(@D)/BasicUsageEnvironment
	$(if $(filter y,$(BR2_PACKAGE_PRUDYNT_T_HYBRID) $(BR2_PACKAGE_PRUDYNT_T_STATIC)), \
		cd $(@D)/groupsock && $(TARGET_AR) cr libgroupsock.a *.o && \
		cd $(@D)/liveMedia && $(TARGET_AR) cr libliveMedia.a *.o && \
		cd $(@D)/UsageEnvironment && $(TARGET_AR) cr libUsageEnvironment.a *.o && \
		cd $(@D)/BasicUsageEnvironment && $(TARGET_AR) cr libBasicUsageEnvironment.a *.o \
	)
endef

# Install only the libraries, skip test programs and servers
# Install both shared and static versions (if built)
override define LIVE555_INSTALL_STAGING_CMDS
	$(TARGET_MAKE_ENV) $(MAKE) DESTDIR=$(STAGING_DIR) -C $(@D)/groupsock install
	$(TARGET_MAKE_ENV) $(MAKE) DESTDIR=$(STAGING_DIR) -C $(@D)/liveMedia install
	$(TARGET_MAKE_ENV) $(MAKE) DESTDIR=$(STAGING_DIR) -C $(@D)/UsageEnvironment install
	$(TARGET_MAKE_ENV) $(MAKE) DESTDIR=$(STAGING_DIR) -C $(@D)/BasicUsageEnvironment install
	$(if $(filter y,$(BR2_PACKAGE_PRUDYNT_T_HYBRID) $(BR2_PACKAGE_PRUDYNT_T_STATIC)), \
		$(INSTALL) -D -m 0644 $(@D)/groupsock/libgroupsock.a $(STAGING_DIR)/usr/lib/libgroupsock.a && \
		$(INSTALL) -D -m 0644 $(@D)/liveMedia/libliveMedia.a $(STAGING_DIR)/usr/lib/libliveMedia.a && \
		$(INSTALL) -D -m 0644 $(@D)/UsageEnvironment/libUsageEnvironment.a $(STAGING_DIR)/usr/lib/libUsageEnvironment.a && \
		$(INSTALL) -D -m 0644 $(@D)/BasicUsageEnvironment/libBasicUsageEnvironment.a $(STAGING_DIR)/usr/lib/libBasicUsageEnvironment.a \
	)
endef

override define LIVE555_INSTALL_TARGET_CMDS
	$(if $(filter y,$(BR2_PACKAGE_PRUDYNT_T_DYNAMIC)), \
		$(TARGET_MAKE_ENV) $(MAKE) DESTDIR=$(TARGET_DIR) PREFIX=/usr -C $(@D)/groupsock install && \
		$(TARGET_MAKE_ENV) $(MAKE) DESTDIR=$(TARGET_DIR) PREFIX=/usr -C $(@D)/liveMedia install && \
		$(TARGET_MAKE_ENV) $(MAKE) DESTDIR=$(TARGET_DIR) PREFIX=/usr -C $(@D)/UsageEnvironment install && \
		$(TARGET_MAKE_ENV) $(MAKE) DESTDIR=$(TARGET_DIR) PREFIX=/usr -C $(@D)/BasicUsageEnvironment install \
	)
endef

#override LIVE555_CFLAGS += \
#	-DALLOW_RTSP_SERVER_PORT_REUSE \
#	-DNO_STD_LIB \
#	-DNO_OPENSSL

endif # BR2_PACKAGE_THINGINO_LIVE555
