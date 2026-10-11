THINGINO_AGENT_SITE_METHOD = local
THINGINO_AGENT_SITE = $(THINGINO_AGENT_PKGDIR)/files
THINGINO_AGENT_LICENSE = MIT
ifeq ($(BR2_PACKAGE_MBEDTLS),y)
THINGINO_AGENT_DEPENDENCIES = thingino-core thingino-jct mbedtls mbedtls-certgen
else ifeq ($(BR2_PACKAGE_THINGINO_MBEDTLS),y)
THINGINO_AGENT_DEPENDENCIES = thingino-core thingino-jct thingino-mbedtls mbedtls-certgen
endif

define THINGINO_AGENT_BUILD_CMDS
	$(TARGET_CC) $(TARGET_CFLAGS) $(TARGET_LDFLAGS) -o $(@D)/agentd-native \
		$(@D)/agentd-native.c
	$(TARGET_CC) $(TARGET_CFLAGS) $(TARGET_LDFLAGS) -o $(@D)/agent-tls-proxy \
		$(@D)/agent-tls-proxy.c $(@D)/agent-tls-event.c \
		-lmbedtls -lmbedx509 -lmbedcrypto
endef

define THINGINO_AGENT_INSTALL_TARGET_CMDS
	# Stage defaults for later merge by thingino-core
	$(INSTALL) -D -m 0644 $(THINGINO_AGENT_PKGDIR)/files/agent.json \
		$(TARGET_DIR)/usr/share/thingino-defaults/20-agent.json

	$(INSTALL) -D -m 0755 $(@D)/S95agent \
		$(TARGET_DIR)/etc/init.d/S95agent
	$(INSTALL) -D -m 0755 $(@D)/agentd \
		$(TARGET_DIR)/usr/sbin/agentd
	$(INSTALL) -D -m 0755 $(@D)/agentd-native \
		$(TARGET_DIR)/usr/libexec/agent/listener
	$(INSTALL) -D -m 0755 $(@D)/agent-tls-proxy \
		$(TARGET_DIR)/usr/libexec/agent/tls-proxy
	$(INSTALL) -D -m 0755 $(@D)/agentctl \
		$(TARGET_DIR)/usr/sbin/agentctl
	$(INSTALL) -D -m 0644 $(@D)/agent-lib \
		$(TARGET_DIR)/usr/libexec/agent/lib.sh
endef

# The null adapter is only a fallback for images with no streamer-provided
# adapter. Install it at finalize time, after the per-package targets are
# merged. That merge is sorted alphabetically, and prudynt-t/thingino-raptor
# sort before thingino-agent, so a null adapter staged at install time would
# overwrite the real one. Skip it when a streamer already provided an adapter.
define THINGINO_AGENT_INSTALL_ADAPTER_FALLBACK
	if [ ! -e "$(TARGET_DIR)/usr/libexec/agent/adapter.sh" ]; then \
		$(INSTALL) -D -m 0644 $(THINGINO_AGENT_PKGDIR)/files/agent-adapter-null \
			$(TARGET_DIR)/usr/libexec/agent/adapter.sh; \
	fi
endef
THINGINO_AGENT_TARGET_FINALIZE_HOOKS += THINGINO_AGENT_INSTALL_ADAPTER_FALLBACK

$(eval $(generic-package))
