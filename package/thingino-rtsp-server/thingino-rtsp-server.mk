THINGINO_RTSP_SERVER_VERSION = 1.0.0
THINGINO_RTSP_SERVER_SITE = $(THINGINO_RTSP_SERVER_PKGDIR)/src
THINGINO_RTSP_SERVER_SITE_METHOD = local
THINGINO_RTSP_SERVER_LICENSE = MIT
THINGINO_RTSP_SERVER_LICENSE_FILES = LICENSE

THINGINO_RTSP_SERVER_INSTALL_STAGING = YES

# Pure C implementation - no C++ dependencies
THINGINO_RTSP_SERVER_CFLAGS = $(TARGET_CFLAGS) -std=c99 -Wall -Wextra -Os
THINGINO_RTSP_SERVER_LDFLAGS = $(TARGET_LDFLAGS)

# No dependencies on C++ libraries
THINGINO_RTSP_SERVER_DEPENDENCIES =

define THINGINO_RTSP_SERVER_BUILD_CMDS
	# Build object files
	$(TARGET_CC) $(THINGINO_RTSP_SERVER_CFLAGS) -c -o $(@D)/rtsp_server.o $(@D)/rtsp_server.c
	$(TARGET_CC) $(THINGINO_RTSP_SERVER_CFLAGS) -c -o $(@D)/rtp_utils.o $(@D)/rtp_utils.c
	$(TARGET_CC) $(THINGINO_RTSP_SERVER_CFLAGS) -c -o $(@D)/sdp_utils.o $(@D)/sdp_utils.c
	$(TARGET_CC) $(THINGINO_RTSP_SERVER_CFLAGS) -c -o $(@D)/test_pattern.o $(@D)/test_pattern.c
	$(TARGET_CC) $(THINGINO_RTSP_SERVER_CFLAGS) -c -o $(@D)/main.o $(@D)/main.c

	# Create static library
	$(TARGET_AR) rcs $(@D)/libthingino-rtsp.a $(@D)/rtsp_server.o $(@D)/rtp_utils.o $(@D)/sdp_utils.o $(@D)/test_pattern.o

	# Build executable
	$(TARGET_CC) $(THINGINO_RTSP_SERVER_CFLAGS) \
		-o $(@D)/thingino-rtsp-server \
		$(@D)/main.o $(@D)/libthingino-rtsp.a \
		$(THINGINO_RTSP_SERVER_LDFLAGS) -lpthread -lm
endef

define THINGINO_RTSP_SERVER_INSTALL_STAGING_CMDS
	$(INSTALL) -D -m 0644 $(@D)/rtsp_server.h $(STAGING_DIR)/usr/include/rtsp_server.h
	$(INSTALL) -D -m 0644 $(@D)/libthingino-rtsp.a $(STAGING_DIR)/usr/lib/libthingino-rtsp.a
endef

define THINGINO_RTSP_SERVER_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/thingino-rtsp-server $(TARGET_DIR)/usr/bin/thingino-rtsp-server
	$(INSTALL) -D -m 0644 $(THINGINO_RTSP_SERVER_PKGDIR)/files/rtsp-server.conf $(TARGET_DIR)/etc/rtsp-server.conf
endef

$(eval $(generic-package))
