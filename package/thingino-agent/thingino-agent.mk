THINGINO_AGENT_SITE_METHOD = local
THINGINO_AGENT_SITE = $(THINGINO_AGENT_PKGDIR)/files
THINGINO_AGENT_LICENSE = MIT
ifeq ($(BR2_PACKAGE_MBEDTLS),y)
THINGINO_AGENT_DEPENDENCIES = thingino-core thingino-jct host-thingino-jct mbedtls mbedtls-certgen
else ifeq ($(BR2_PACKAGE_THINGINO_MBEDTLS),y)
THINGINO_AGENT_DEPENDENCIES = thingino-core thingino-jct host-thingino-jct thingino-mbedtls mbedtls-certgen
endif

define THINGINO_AGENT_BUILD_CMDS
	$(TARGET_CC) $(TARGET_CFLAGS) $(TARGET_LDFLAGS) -o $(@D)/thingino-agentd-native \
		$(@D)/thingino-agentd-native.c
	$(TARGET_CC) $(TARGET_CFLAGS) $(TARGET_LDFLAGS) -o $(@D)/thingino-agent-tls-proxy \
		$(@D)/thingino-agent-tls-proxy.c $(@D)/thingino-agent-tls-event.c \
		-lmbedtls -lmbedx509 -lmbedcrypto
endef

define THINGINO_AGENT_INSTALL_TARGET_CMDS
	$(HOST_DIR)/bin/jct $(TARGET_DIR)/etc/thingino.json import \
		$(THINGINO_AGENT_PKGDIR)/files/thingino-agent.json

	$(INSTALL) -D -m 0755 $(@D)/S95thingino-agent \
		$(TARGET_DIR)/etc/init.d/S95thingino-agent
	$(INSTALL) -D -m 0755 $(@D)/thingino-agentd \
		$(TARGET_DIR)/usr/sbin/thingino-agentd
	$(INSTALL) -D -m 0755 $(@D)/thingino-agentd-native \
		$(TARGET_DIR)/usr/libexec/thingino-agent/listener
	$(INSTALL) -D -m 0755 $(@D)/thingino-agent-tls-proxy \
		$(TARGET_DIR)/usr/libexec/thingino-agent/tls-proxy
	$(INSTALL) -D -m 0755 $(@D)/thingino-agentctl \
		$(TARGET_DIR)/usr/sbin/thingino-agentctl
	$(INSTALL) -D -m 0644 $(@D)/thingino-agent-lib \
		$(TARGET_DIR)/usr/libexec/thingino-agent/lib.sh
	$(INSTALL) -D -m 0644 $(@D)/thingino-agent-adapter-null \
		$(TARGET_DIR)/usr/libexec/thingino-agent/adapters/null.sh
	$(INSTALL) -D -m 0644 $(@D)/thingino-agent-adapter-prudynt \
		$(TARGET_DIR)/usr/libexec/thingino-agent/adapters/prudynt.sh
endef

$(eval $(generic-package))