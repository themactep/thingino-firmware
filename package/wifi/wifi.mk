WIFI_SITE_METHOD = local
WIFI_SITE = $(BR2_EXTERNAL)/package/wifi

WIFI_TEMPLATE_PYTHON = $(shell command -v python3)
WIFI_TEMPLATE_RENDERER = $(BR2_EXTERNAL)/scripts/render_template.py

ifeq ($(BR2_PACKAGE_WIFI),y)
WIFI_DRIVER_SELECTED :=
WIFI_DRIVER_BR2_PACKAGE :=

define WIFI_ADD_DRIVER
WIFI_DRIVER_INTERFACE_$2 := $3
WIFI_DRIVER_BR2_NAME_$2 := $1
ifeq ($$($1),y)
WIFI_DRIVER_SELECTED += $2
WIFI_DRIVER_BR2_PACKAGE := $1
endif
endef

WIFI_AIC8800_INTERFACE := $(if $(BR2_PACKAGE_WIFI_AIC8800_SDIO),sdio,$(if $(BR2_PACKAGE_WIFI_AIC8800_PCIE),pcie,usb))
WIFI_WS73V100_INTERFACE := $(if $(BR2_PACKAGE_WIFI_WS73V100_USB),usb,sdio)

$(eval $(call WIFI_ADD_DRIVER,BR2_PACKAGE_WIFI_AIC8800,aic8800_fdrv,$(WIFI_AIC8800_INTERFACE)))
$(eval $(call WIFI_ADD_DRIVER,BR2_PACKAGE_WIFI_ATBM6012B,atbm6012b,usb))
$(eval $(call WIFI_ADD_DRIVER,BR2_PACKAGE_WIFI_ATBM6012BX,atbm6012bx,usb))
$(eval $(call WIFI_ADD_DRIVER,BR2_PACKAGE_WIFI_ATBM6031,atbm6031,sdio))
$(eval $(call WIFI_ADD_DRIVER,BR2_PACKAGE_WIFI_ATBM6031X,atbm6031x,sdio))
$(eval $(call WIFI_ADD_DRIVER,BR2_PACKAGE_WIFI_ATBM6032,atbm6032,usb))
$(eval $(call WIFI_ADD_DRIVER,BR2_PACKAGE_WIFI_ATBM6032X,atbm6032x,usb))
$(eval $(call WIFI_ADD_DRIVER,BR2_PACKAGE_WIFI_ATBM6041,atbm6041,sdio))
$(eval $(call WIFI_ADD_DRIVER,BR2_PACKAGE_WIFI_ATBM6132S,atbm6132s,sdio))
$(eval $(call WIFI_ADD_DRIVER,BR2_PACKAGE_WIFI_ATBM6132U,atbm6132u,usb))
$(eval $(call WIFI_ADD_DRIVER,BR2_PACKAGE_WIFI_ATBM6062S,atbm6062s,sdio))
$(eval $(call WIFI_ADD_DRIVER,BR2_PACKAGE_WIFI_ATBM6062CU,atbm6062cu,usb))
$(eval $(call WIFI_ADD_DRIVER,BR2_PACKAGE_WIFI_ATBM6062U,atbm6062u,usb))
$(eval $(call WIFI_ADD_DRIVER,BR2_PACKAGE_WIFI_ATBM6441,atbm6441,sdio))
$(eval $(call WIFI_ADD_DRIVER,BR2_PACKAGE_WIFI_ATK9,atk9,usb))
$(eval $(call WIFI_ADD_DRIVER,BR2_PACKAGE_WIFI_BCM43438,bcmdhd,sdio))
$(eval $(call WIFI_ADD_DRIVER,BR2_PACKAGE_WIFI_BCMDHD_AP6214A,bcmdhd,sdio))
$(eval $(call WIFI_ADD_DRIVER,BR2_PACKAGE_WIFI_HI3881,hi3881,sdio))
$(eval $(call WIFI_ADD_DRIVER,BR2_PACKAGE_WIFI_MT7601U,mt7601sta,usb))
$(eval $(call WIFI_ADD_DRIVER,BR2_PACKAGE_WIFI_RTL8188EU,8188eu,usb))
$(eval $(call WIFI_ADD_DRIVER,BR2_PACKAGE_WIFI_RTL8188EUS,8188eu,usb))
$(eval $(call WIFI_ADD_DRIVER,BR2_PACKAGE_WIFI_RTL8188FU,8188fu,usb))
$(eval $(call WIFI_ADD_DRIVER,BR2_PACKAGE_WIFI_RTL8189ES,8189es,sdio))
$(eval $(call WIFI_ADD_DRIVER,BR2_PACKAGE_WIFI_RTL8189FS,8189fs,sdio))
$(eval $(call WIFI_ADD_DRIVER,BR2_PACKAGE_WIFI_RTL8192FS,8192fs,sdio))
$(eval $(call WIFI_ADD_DRIVER,BR2_PACKAGE_WIFI_RTL8192EU,8192eu,usb))
$(eval $(call WIFI_ADD_DRIVER,BR2_PACKAGE_WIFI_RTL8812AU,8812au,usb))
$(eval $(call WIFI_ADD_DRIVER,BR2_PACKAGE_WIFI_RTL8733BU,8733bu,usb))
$(eval $(call WIFI_ADD_DRIVER,BR2_PACKAGE_WIFI_SSV6X5X,ssv6x5x,usb))
$(eval $(call WIFI_ADD_DRIVER,BR2_PACKAGE_WIFI_SSV6158,ssv6158,sdio))
$(eval $(call WIFI_ADD_DRIVER,BR2_PACKAGE_WIFI_SSW101B,ssw101b,usb))
$(eval $(call WIFI_ADD_DRIVER,BR2_PACKAGE_WIFI_SYN4343,bcmdhd,sdio))
$(eval $(call WIFI_ADD_DRIVER,BR2_PACKAGE_WIFI_TXW901U,txw901u,usb))
$(eval $(call WIFI_ADD_DRIVER,BR2_PACKAGE_WIFI_WS73V100,ws73v100,$(WIFI_WS73V100_INTERFACE)))
$(eval $(call WIFI_ADD_DRIVER,BR2_PACKAGE_WIFI_WQ9001,wq9001,usb))

WIFI_DRIVER_SELECTED := $(strip $(WIFI_DRIVER_SELECTED))

ifeq ($(WIFI_DRIVER_SELECTED),)
$(error No Thingino Wi-Fi driver (BR2_PACKAGE_WIFI_*) selected)
endif
ifneq ($(words $(WIFI_DRIVER_SELECTED)),1)
$(error Multiple Thingino Wi-Fi drivers selected: $(WIFI_DRIVER_SELECTED))
endif

WLAN_MODULE := $(firstword $(WIFI_DRIVER_SELECTED))
WIFI_INTERFACE := $(strip $(WIFI_DRIVER_INTERFACE_$(WLAN_MODULE)))

WIFI_NETDEV = wlan0
ifeq ($(BR2_PACKAGE_WIFI_HI3881),y)
WIFI_NETDEV = ap0
else ifeq ($(BR2_PACKAGE_WIFI_WQ9001),y)
WIFI_NETDEV = wlan1
endif

ifeq ($(WIFI_INTERFACE),)
$(error Thingino Wi-Fi driver '$(WLAN_MODULE)' is missing interface metadata)
endif

# Extract the driver package prefix (e.g., BR2_PACKAGE_WIFI_BCM43438 -> BCM43438)
WIFI_DRIVER_PREFIX := $(patsubst BR2_PACKAGE_WIFI_%,%,$(WIFI_DRIVER_BR2_PACKAGE))

# Get the MODULE_NAME and MODULE_OPTS from the driver package
# Convert to uppercase for variable lookup (e.g., BCM43438_MODULE_NAME)
WLAN_MODULE_NAME := $($(WIFI_DRIVER_PREFIX)_MODULE_NAME)
WLAN_MODULE_OPTS := $($(WIFI_DRIVER_PREFIX)_MODULE_OPTS)

WIFI_MODULE_IS_SDIO_FLAG := $(if $(filter sdio,$(WIFI_INTERFACE)),1,0)

ifeq ($(WLAN_MODULE),hi3881)
WIFI_IS_HI3881_FLAG := 1
else
WIFI_IS_HI3881_FLAG := 0
endif

WIFI_IS_FAMILY_AIC_FLAG := $(if $(filter aic%,$(WLAN_MODULE)),1,0)
WIFI_IS_FAMILY_ATBM_FLAG := $(if $(filter atbm%,$(WLAN_MODULE)),1,0)
WIFI_IS_FAMILY_BCM_FLAG := $(if $(filter bcm% syn%,$(WLAN_MODULE)),1,0)
WIFI_IS_FAMILY_HI_FLAG := $(if $(filter hi%,$(WLAN_MODULE)),1,0)
WIFI_IS_FAMILY_MTK_FLAG := $(if $(filter mt7%,$(WLAN_MODULE)),1,0)
WIFI_IS_FAMILY_RTL_FLAG := $(if $(filter rtl% 818% 87% 88%,$(WLAN_MODULE)),1,0)
WIFI_IS_FAMILY_SSV_FLAG := $(if $(filter ssv%,$(WLAN_MODULE)),1,0)

WIFI_SDIO_SET_GPIO_FLAG := 0
WIFI_SDIO_RETURN_EARLY_FLAG := 0
WIFI_SDIO_UNSUPPORTED_FLAG := 0

ifeq ($(WIFI_MODULE_IS_SDIO_FLAG),1)
	ifneq ($(filter $(SOC_FAMILY),t23 t31),)
		ifeq ($(SOC_MODEL),t31a)
			WIFI_SDIO_RETURN_EARLY_FLAG := 1
		else
			WIFI_SDIO_SET_GPIO_FLAG := 1
		endif
	else ifneq ($(filter $(SOC_FAMILY),t10 t20 t21 t30 t40 t41),)
		# Skip mmc_gpio but still send MMC insert
	else
		WIFI_SDIO_UNSUPPORTED_FLAG := 1
	endif
endif

WIFI_TEMPLATE_VARS = \
	--var WLAN_MODULE=$(WLAN_MODULE) \
	--var WLAN_MODULE_NAME=$(WLAN_MODULE_NAME) \
	--var WLAN_MODULE_OPTS=$(WLAN_MODULE_OPTS) \
	--var SOC_FAMILY=$(SOC_FAMILY) \
	--var SOC_MODEL=$(SOC_MODEL) \
	--var WIFI_MODULE_IS_SDIO=$(WIFI_MODULE_IS_SDIO_FLAG) \
	--var WIFI_SDIO_SET_GPIO=$(WIFI_SDIO_SET_GPIO_FLAG) \
	--var WIFI_SDIO_RETURN_EARLY=$(WIFI_SDIO_RETURN_EARLY_FLAG) \
	--var WIFI_SDIO_UNSUPPORTED=$(WIFI_SDIO_UNSUPPORTED_FLAG) \
	--var WIFI_IS_HI3881=$(WIFI_IS_HI3881_FLAG) \
	--var WIFI_FAMILY_AIC=$(WIFI_IS_FAMILY_AIC_FLAG) \
	--var WIFI_FAMILY_ATBM=$(WIFI_IS_FAMILY_ATBM_FLAG) \
	--var WIFI_FAMILY_BCM=$(WIFI_IS_FAMILY_BCM_FLAG) \
	--var WIFI_FAMILY_HI=$(WIFI_IS_FAMILY_HI_FLAG) \
	--var WIFI_FAMILY_MTK=$(WIFI_IS_FAMILY_MTK_FLAG) \
	--var WIFI_FAMILY_RTL=$(WIFI_IS_FAMILY_RTL_FLAG) \
	--var WIFI_FAMILY_SSV=$(WIFI_IS_FAMILY_SSV_FLAG)

define WIFI_LINUX_CONFIG_FIXUPS
	$(call KCONFIG_SET_OPT,CONFIG_RFKILL,y)
endef

define WIFI_INSTALL_TARGET_CMDS
	$(INSTALL) -d $(TARGET_DIR)/etc/init.d

	# Wireless service script
	$(WIFI_TEMPLATE_PYTHON) $(WIFI_TEMPLATE_RENDERER) --template $(WIFI_PKGDIR)/files/S36wireless.in \
		--output $(TARGET_DIR)/etc/init.d/S36wireless $(WIFI_TEMPLATE_VARS)
	chmod 0755 $(TARGET_DIR)/etc/init.d/S36wireless

	# WPA supplicant script
	$(INSTALL) -D -m 0755 $(WIFI_PKGDIR)/files/S38wpa_supplicant \
		$(TARGET_DIR)/etc/init.d/S38wpa_supplicant

	# Network interface config
	$(INSTALL) -D -m 0644 $(WIFI_PKGDIR)/files/wlan0 \
		$(TARGET_DIR)/etc/network/interfaces.d/wlan0

	# MMC GPIO config
	if [ "$(BR2_PACKAGE_THINGINO_KOPT_MMC1_PA_4BIT)" = "y" ]; then \
		$(INSTALL) -D -m 0755 $(WIFI_PKGDIR)/files/mmc_gpio_pa \
			$(TARGET_DIR)/usr/sbin/mmc_gpio ; \
	else \
		$(INSTALL) -D -m 0755 $(WIFI_PKGDIR)/files/mmc_gpio_pb \
			$(TARGET_DIR)/usr/sbin/mmc_gpio ; \
	fi

	# CLI tool
	$(INSTALL) -d $(TARGET_DIR)/usr/sbin
	$(WIFI_TEMPLATE_PYTHON) $(WIFI_TEMPLATE_RENDERER) --template $(WIFI_PKGDIR)/files/wlan.in \
		--output $(TARGET_DIR)/usr/sbin/wlan $(WIFI_TEMPLATE_VARS)
	chmod 0755 $(TARGET_DIR)/usr/sbin/wlan

	ln -sfr $(TARGET_DIR)/usr/sbin/wlan $(TARGET_DIR)/usr/sbin/wlancli
	ln -sfr $(TARGET_DIR)/usr/sbin/wlan $(TARGET_DIR)/usr/sbin/wlaninfo
	ln -sfr $(TARGET_DIR)/usr/sbin/wlan $(TARGET_DIR)/usr/sbin/wlanreset
	ln -sfr $(TARGET_DIR)/usr/sbin/wlan $(TARGET_DIR)/usr/sbin/wlanrssi
	ln -sfr $(TARGET_DIR)/usr/sbin/wlan $(TARGET_DIR)/usr/sbin/wlansetup
	ln -sfr $(TARGET_DIR)/usr/sbin/wlan $(TARGET_DIR)/usr/sbin/wlantemp

	# Captive Portal
	$(INSTALL) -D -m 0644 $(WIFI_PKGDIR)/files/wpa_supplicant.conf \
		$(TARGET_DIR)/etc/wpa_supplicant.conf
	$(INSTALL) -D -m 0755 $(WIFI_PKGDIR)/files/disable_wlan \
		$(TARGET_DIR)/etc/network/if-pre-up.d/disable_wlan
	$(INSTALL) -D -m 0644 $(WIFI_PKGDIR)/files/dnsd-portal.conf \
		$(TARGET_DIR)/etc/dnsd-portal.conf
	$(INSTALL) -D -m 0644 $(WIFI_PKGDIR)/files/httpd-portal.conf \
		$(TARGET_DIR)/etc/httpd-portal.conf
	$(INSTALL) -D -m 0644 $(WIFI_PKGDIR)/files/udhcpd-portal.conf \
		$(TARGET_DIR)/etc/udhcpd-portal.conf
	$(INSTALL) -D -m 0644 $(WIFI_PKGDIR)/files/favicon.ico \
		$(TARGET_DIR)/var/www-portal/favicon.ico
	$(INSTALL) -D -m 0644 $(WIFI_PKGDIR)/files/index.html \
		$(TARGET_DIR)/var/www-portal/index.html
	$(INSTALL) -D -m 0644 $(WIFI_PKGDIR)/files/portal.min.js \
		$(TARGET_DIR)/var/www-portal/portal.min.js
	$(INSTALL) -D -m 0644 $(WIFI_PKGDIR)/files/portal.min.css \
		$(TARGET_DIR)/var/www-portal/portal.min.css
	$(INSTALL) -D -m 0644 $(WIFI_PKGDIR)/files/logo.svg \
		$(TARGET_DIR)/var/www-portal/logo.svg
	$(INSTALL) -D -m 0755 $(WIFI_PKGDIR)/files/portal.cgi \
		$(TARGET_DIR)/var/www-portal/x/portal.cgi
	$(INSTALL) -D -m 0755 $(WIFI_PKGDIR)/files/api.cgi \
		$(TARGET_DIR)/var/www-portal/x/api.cgi
endef

# MT7601u wifi driver needs a PSK for the portal AP to function
ifeq ($(BR2_PACKAGE_WIFI_MT7601U),y)
define MODIFY_INSTALL_CONFIGS
	sed -i '/key_mgmt/s/NONE/WPA-PSK/' $(TARGET_DIR)/etc/wpa_supplicant.conf
	sed -i '/network={/a\      psk="thingino"' $(TARGET_DIR)/etc/wpa_supplicant.conf
endef
endif

WIFI_POST_INSTALL_TARGET_HOOKS += MODIFY_INSTALL_CONFIGS

$(eval $(generic-package))

endif
