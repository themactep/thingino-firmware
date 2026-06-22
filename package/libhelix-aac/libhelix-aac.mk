LIBHELIX_AAC_VERSION = 2.4.1
LIBHELIX_AAC_SITE = $(call github,earlephilhower,ESP8266Audio,$(LIBHELIX_AAC_VERSION))
LIBHELIX_AAC_LICENSE = RPSL-1.0
LIBHELIX_AAC_LICENSE_FILES = src/libhelix-mp3/LICENSE.txt src/libhelix-mp3/RPSL.txt

LIBHELIX_AAC_INSTALL_STAGING = YES
LIBHELIX_AAC_INSTALL_TARGET = YES

define LIBHELIX_AAC_BUILD_CMDS
	$(foreach src, $(wildcard $(@D)/src/libhelix-aac/*.c), \
		$(TARGET_CC) $(TARGET_CFLAGS) -I$(@D)/src/libhelix-aac -fPIC -DUSE_DEFAULT_STDLIB -c $(src) -o $(patsubst %.c, %.o, $(src));)
	find $(@D)/src/libhelix-aac -type f -name '*.o' | xargs $(TARGET_CC) $(TARGET_LDFLAGS) -shared -o $(@D)/libhelix-aac.so
endef

define LIBHELIX_AAC_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/libhelix-aac.so $(TARGET_DIR)/usr/lib/libhelix-aac.so
endef

define LIBHELIX_AAC_INSTALL_STAGING_CMDS
	$(INSTALL) -D -m 0755 $(@D)/libhelix-aac.so $(STAGING_DIR)/usr/lib/libhelix-aac.so
	find $(@D)/src/libhelix-aac -type f -name '*.h' -exec $(INSTALL) -D -m 0644 {} $(STAGING_DIR)/usr/include/ \;
endef

$(eval $(generic-package))

