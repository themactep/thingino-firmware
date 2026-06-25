LIBHELIX_AAC_VERSION = 2.4.1
LIBHELIX_AAC_SITE = $(call github,earlephilhower,ESP8266Audio,$(LIBHELIX_AAC_VERSION))
LIBHELIX_AAC_LICENSE = RPSL-1.0
LIBHELIX_AAC_LICENSE_FILES = src/libhelix-mp3/LICENSE.txt src/libhelix-mp3/RPSL.txt

LIBHELIX_AAC_INSTALL_STAGING = YES
LIBHELIX_AAC_INSTALL_TARGET = YES

LIBHELIX_AAC_SRC_DIR = src/libhelix-aac
LIBHELIX_AAC_SO_NAME = libhelix-aac.so

define LIBHELIX_AAC_BUILD_CMDS
	$(foreach src,$(wildcard $(@D)/$(LIBHELIX_AAC_SRC_DIR)/*.c), \
		$(TARGET_CC) $(TARGET_CFLAGS) -I$(@D)/$(LIBHELIX_AAC_SRC_DIR) -fPIC -DUSE_DEFAULT_STDLIB -c $(src) -o $(patsubst %.c, %.o, $(src));)
	find $(@D)/$(LIBHELIX_AAC_SRC_DIR) -type f -name '*.o' | xargs $(TARGET_CC) $(TARGET_LDFLAGS) -shared -o $(@D)/$(LIBHELIX_AAC_SO_NAME)
endef

define LIBHELIX_AAC_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/$(LIBHELIX_AAC_SO_NAME) $(TARGET_DIR)/usr/lib/$(LIBHELIX_AAC_SO_NAME)
endef

define LIBHELIX_AAC_INSTALL_STAGING_CMDS
	$(INSTALL) -D -m 0755 $(@D)/$(LIBHELIX_AAC_SO_NAME) $(STAGING_DIR)/usr/lib/$(LIBHELIX_AAC_SO_NAME)
	find $(@D)/$(LIBHELIX_AAC_SRC_DIR) -type f -name '*.h' -exec $(INSTALL) -D -m 0644 {} $(STAGING_DIR)/usr/include/ \;
endef

$(eval $(generic-package))
