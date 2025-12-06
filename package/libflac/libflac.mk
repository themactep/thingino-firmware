LIBFLAC_SITE_METHOD = git
LIBFLAC_SITE = https://github.com/earlephilhower/ESP8266Audio.git
LIBFLAC_SITE_BRANCH = master
LIBFLAC_VERSION = 94c68ecbaa5489bba3073c46475f2e46effe2c97

LIBFLAC_INSTALL_STAGING = YES
LIBFLAC_INSTALL_TARGET = YES

LIBFLAC_SRC_DIR = src/libflac
LIBFLAC_SO_NAME = libflac-lite.so

define LIBFLAC_BUILD_CMDS
	$(foreach src,$(wildcard $(@D)/$(LIBFLAC_SRC_DIR)/*.c), \
		$(TARGET_CC) $(TARGET_CFLAGS) -I$(@D)/$(LIBFLAC_SRC_DIR) -I$(LIBFLAC_PKGDIR)/arduino_compat -fPIC -DUSE_DEFAULT_STDLIB -c $(src) -o $(patsubst %.c, %.o, $(src));)
	find $(@D)/$(LIBFLAC_SRC_DIR) -type f -name '*.o' | xargs $(TARGET_CC) $(TARGET_LDFLAGS) -shared -o $(@D)/$(LIBFLAC_SO_NAME)
endef

define LIBFLAC_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/$(LIBFLAC_SO_NAME) $(TARGET_DIR)/usr/lib/$(LIBFLAC_SO_NAME)
endef

define LIBFLAC_INSTALL_STAGING_CMDS
	$(INSTALL) -D -m 0755 $(@D)/$(LIBFLAC_SO_NAME) $(STAGING_DIR)/usr/lib/$(LIBFLAC_SO_NAME)
	mkdir -p $(STAGING_DIR)/usr/include
	rm -rf $(STAGING_DIR)/usr/include/FLAC
	cp -r $(@D)/$(LIBFLAC_SRC_DIR)/FLAC $(STAGING_DIR)/usr/include/
	find $(@D)/$(LIBFLAC_SRC_DIR) -maxdepth 1 -type f -name '*.h' -exec $(INSTALL) -D -m 0644 {} $(STAGING_DIR)/usr/include/ \;
endef

$(eval $(generic-package))
