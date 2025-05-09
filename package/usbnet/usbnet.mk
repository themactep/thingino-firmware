USBNET_VERSION = 1.0
USBNET_SITE_METHOD = local
USBNET_SITE = $(USBNET_PKGDIR)/files


ifeq ($(BR2_PACKAGE_USBNET_USB_DIRECT_NCM),y)
USBNET_INSTALL_TARGET_CMDS = \
	$(INSTALL) -D -m 0755 $(USBNET_PKGDIR)/files/S36cdcnet \
		$(TARGET_DIR)/etc/init.d/S36cdcnet; \
	$(INSTALL) -D -m 0644 $(USBNET_PKGDIR)/files/usb0-cdc \
		$(TARGET_DIR)/etc/network/interfaces.d/usb0; \
	$(INSTALL) -D -m 0644 $(USBNET_PKGDIR)/files/udhcpd.conf \
		$(TARGET_DIR)/etc/udhcpd.conf; \
	$(INSTALL) -D -m 0644 $(USBNET_PKGDIR)/files/dnsd.conf \
		$(TARGET_DIR)/etc/dnsd.conf
else ifeq ($(BR2_PACKAGE_USBNET_USB_DIRECT_NCM_CLIENT),y)
USBNET_INSTALL_TARGET_CMDS = \
	$(INSTALL) -D -m 0755 $(USBNET_PKGDIR)/files/S36cdcnet-client \
		$(TARGET_DIR)/etc/init.d/S36cdcnet; \
	$(INSTALL) -D -m 0644 $(USBNET_PKGDIR)/files/usb0 \
		$(TARGET_DIR)/etc/network/interfaces.d/usb0
else
USBNET_INSTALL_TARGET_CMDS = \
	$(INSTALL) -D -m 0644 $(USBNET_PKGDIR)/files/usb0 \
		$(TARGET_DIR)/etc/network/interfaces.d/usb0
endif

ifeq ($(or $(BR2_PACKAGE_USBNET_USB_DIRECT_NCM), $(BR2_PACKAGE_USBNET_USB_DIRECT_NCM_CLIENT)),y)
define USBNET_LINUX_CONFIG_FIXUPS_USB_DIRECT_NCM
	$(call KCONFIG_ENABLE_OPT,CONFIG_USB_LIBCOMPOSITE)
	$(call KCONFIG_ENABLE_OPT,CONFIG_USB_U_ETHER)
	$(call KCONFIG_ENABLE_OPT,CONFIG_USB_F_NCM)
	$(call KCONFIG_SET_OPT,CONFIG_USB_G_NCM,m)
endef
endif

ifeq ($(BR2_PACKAGE_USBNET_WWAN_SERIAL),y)
define USBNET_LINUX_CONFIG_FIXUPS_WWAN_SERIAL
	$(call KCONFIG_SET_OPT,CONFIG_USB_ACM,m)
	$(call KCONFIG_SET_OPT,CONFIG_USB_SERIAL,m)
	$(call KCONFIG_SET_OPT,CONFIG_USB_SERIAL_WWAN,m)
	$(call KCONFIG_ENABLE_OPT,CONFIG_USB_SERIAL_GENERIC)
	$(call KCONFIG_SET_OPT,CONFIG_USB_SERIAL_OPTION,m)
endef
define USBNET_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(USBNET_PKGDIR)/files/S38usbnet \
		$(TARGET_DIR)/etc/init.d/S38usbnet
endef
endif

ifeq ($(BR2_PACKAGE_USBNET_RNDIS),y)
define USBNET_LINUX_CONFIG_FIXUPS_RNDIS
	$(call KCONFIG_ENABLE_OPT,CONFIG_USB_USBNET)
	$(call KCONFIG_SET_OPT,CONFIG_USB_NET_RNDIS_HOST,m)
endef
endif

ifeq ($(BR2_PACKAGE_USBNET_CDC_ETHER),y)
define USBNET_LINUX_CONFIG_FIXUPS_CDC_ETHER
	$(call KCONFIG_ENABLE_OPT,CONFIG_USB_USBNET)
	$(call KCONFIG_ENABLE_OPT,CONFIG_USB_NET_CDCETHER)
endef
endif

ifeq ($(BR2_PACKAGE_USBNET_CDC_NCM),y)
define USBNET_LINUX_CONFIG_FIXUPS_CDC_NCM
	$(call KCONFIG_ENABLE_OPT,CONFIG_USB_USBNET)
	$(call KCONFIG_ENABLE_OPT,CONFIG_USB_NET_CDC_NCM)
endef
endif

ifeq ($(BR2_PACKAGE_USBNET_ASIX),y)
define USBNET_LINUX_CONFIG_FIXUPS_ASIX
	$(call KCONFIG_ENABLE_OPT,CONFIG_USB_USBNET)
	$(call KCONFIG_ENABLE_OPT,CONFIG_USB_NET_AX8817X)
endef
endif

ifeq ($(BR2_PACKAGE_USBNET_ASIX_179_178A),y)
define USBNET_LINUX_CONFIG_FIXUPS_ASIX_179_178A
	$(call KCONFIG_ENABLE_OPT,CONFIG_USB_USBNET)
	$(call KCONFIG_ENABLE_OPT,CONFIG_USB_NET_AX88179_178A)
endef
endif

ifeq ($(BR2_PACKAGE_USBNET_R8152),y)
define USBNET_LINUX_CONFIG_FIXUPS_R8152
	$(call KCONFIG_ENABLE_OPT,CONFIG_USB_USBNET)
	$(call KCONFIG_ENABLE_OPT,CONFIG_USB_RTL8152)
endef
endif

####################################################
#This is required for BR to successfully concatenate the kernel options when used with modules
define USBNET_LINUX_CONFIG_FIXUPS
	$(call USBNET_LINUX_CONFIG_FIXUPS_USB_DIRECT_NCM)
	$(call USBNET_LINUX_CONFIG_FIXUPS_CDC_ETHER)
	$(call USBNET_LINUX_CONFIG_FIXUPS_WWAN_SERIAL)
	$(call USBNET_LINUX_CONFIG_FIXUPS_RNDIS)
	$(call USBNET_LINUX_CONFIG_FIXUPS_ASIX)
	$(call USBNET_LINUX_CONFIG_FIXUPS_ASIX_179_178A)
	$(call USBNET_LINUX_CONFIG_FIXUPS_R8152)
	$(call USBNET_LINUX_CONFIG_FIXUPS_CDC_NCM)
endef

$(eval $(generic-package))

####ADDITIONAL MODES FUTURE

#USBSERIAL:

#CONFIG_USB_SERIAL
#CONFIG_USB_SERIAL_GENERIC
#CONFIG_USB_SERIAL_OPTION
#CONFIG_USB_ACM

#RNDIS:

#CONFIG_USB_SERIAL
#CONFIG_USB_SERIAL_OPTION
#CONFIG_USB_USBNET
#CONFIG_USB_NET_CDCETHER

#PPP:

#CONFIG_USB_SERIAL
#CONFIG_USB_SERIAL_OPTION
#CONFIG_PPP
#CONFIG_PPP_FILTER
#CONFIG_PPP_MULTILINK
#CONFIG_PPP_BSDCOMP
#CONFIG_PPP_ASYNC
#CONFIG_PPP_SYNC_TTY
#CONFIG_PPP_DEFLATE
