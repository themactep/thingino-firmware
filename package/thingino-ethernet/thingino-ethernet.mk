define THINGINO_ETHERNET_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0644 $(THINGINO_ETHERNET_PKGDIR)/files/eth0 \
		$(TARGET_DIR)/etc/network/interfaces.d/eth0
	$(if $(BR2_PACKAGE_THINGINO_KOPT_IPV6),printf '   dhcp-v6-enabled true\n' >> $(TARGET_DIR)/etc/network/interfaces.d/eth0)
endef

ifeq ($(BR2_ETHERNET),y)
define THINGINO_ETHERNET_BUSYBOX_CONFIG_FIXUPS_ETH
	$(call KCONFIG_ENABLE_OPT,CONFIG_IFPLUGD)
endef
endif

define THINGINO_ETHERNET_BUSYBOX_CONFIG_FIXUPS
	$(call THINGINO_ETHERNET_BUSYBOX_CONFIG_FIXUPS_ETH)
endef

ifeq ($(KERNEL_VERSION_5),y)
# 5.15 ethernet is the mainline stmmac/dwmac-ingenic glue (DWMAC_INGENIC
# defaults on with MACH_INGENIC). The generic kernel configs ship the whole
# stack off, so re-enable it here when the board asks for ethernet.
define THINGINO_ETHERNET_LINUX_CONFIG_FIXUPS
	$(call KCONFIG_ENABLE_OPT,CONFIG_STMMAC_ETH)
	$(call KCONFIG_ENABLE_OPT,CONFIG_STMMAC_PLATFORM)
	$(call KCONFIG_ENABLE_OPT,CONFIG_DWMAC_INGENIC)
	$(call KCONFIG_ENABLE_OPT,CONFIG_PHYLIB)
	$(call KCONFIG_ENABLE_OPT,CONFIG_PTP_1588_CLOCK)
	$(call KCONFIG_ENABLE_OPT,CONFIG_NETWORK_PHY_TIMESTAMPING)
	$(call KCONFIG_ENABLE_OPT,CONFIG_MOTORCOMM_PHY)
	$(call KCONFIG_ENABLE_OPT,CONFIG_FIXED_PHY)
endef
endif

ifeq ($(KERNEL_VERSION_7),y)
# 7.x builds the DWMAC stack as modules; the MAC platform device is already
# registered from the device tree, so loading the glue driver triggers probe.
define THINGINO_ETHERNET_INSTALL_MODULES
	$(INSTALL) -m 0755 -d $(TARGET_DIR)/etc/modules.d
	echo dwmac-ingenic > $(TARGET_DIR)/etc/modules.d/40-ethernet
endef
THINGINO_ETHERNET_POST_INSTALL_TARGET_HOOKS += THINGINO_ETHERNET_INSTALL_MODULES
endif

$(eval $(generic-package))
