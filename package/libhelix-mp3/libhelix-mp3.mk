LIBHELIX_MP3_SITE_METHOD = git
LIBHELIX_MP3_SITE = https://github.com/earlephilhower/ESP8266Audio.git
LIBHELIX_MP3_SITE_BRANCH = master
LIBHELIX_MP3_VERSION = 94c68ecbaa5489bba3073c46475f2e46effe2c97

LIBHELIX_MP3_INSTALL_STAGING = YES
LIBHELIX_MP3_INSTALL_TARGET = YES

LIBHELIX_MP3_SRC_DIR = src/libhelix-mp3
LIBHELIX_MP3_SO_NAME = libhelix-mp3.so

define LIBHELIX_MP3_BUILD_CMDS
	$(foreach src,$(wildcard $(@D)/$(LIBHELIX_MP3_SRC_DIR)/*.c), \
		$(TARGET_CC) $(TARGET_CFLAGS) -I$(@D)/$(LIBHELIX_MP3_SRC_DIR) -I$(LIBHELIX_MP3_PKGDIR)/arduino_compat -fPIC -DUSE_DEFAULT_STDLIB -DARDUINO -c $(src) -o $(patsubst %.c, %.o, $(src));)
	find $(@D)/$(LIBHELIX_MP3_SRC_DIR) -type f -name '*.o' | xargs $(TARGET_CC) $(TARGET_LDFLAGS) -shared -o $(@D)/$(LIBHELIX_MP3_SO_NAME)
endef

define LIBHELIX_MP3_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/$(LIBHELIX_MP3_SO_NAME) $(TARGET_DIR)/usr/lib/$(LIBHELIX_MP3_SO_NAME)
endef

define LIBHELIX_MP3_INSTALL_STAGING_CMDS
	$(INSTALL) -D -m 0755 $(@D)/$(LIBHELIX_MP3_SO_NAME) $(STAGING_DIR)/usr/lib/$(LIBHELIX_MP3_SO_NAME)
	find $(@D)/$(LIBHELIX_MP3_SRC_DIR) -type f -name '*.h' -exec $(INSTALL) -D -m 0644 {} $(STAGING_DIR)/usr/include/ \;
endef

$(eval $(generic-package))
