WIFI_SITE_METHOD = local
WIFI_SITE = $(BR2_EXTERNAL)/package/wifi

WIFI_DEPENDENCIES += host-python3

WIFI_TEMPLATE_RENDERER = $(BR2_EXTERNAL)/scripts/render_template.py
WIFI_TEMPLATE_PYTHON = $(HOST_DIR)/bin/python3

WIFI_DRIVER_SELECTED :=
WIFI_DRIVER_INTERFACE :=

define WIFI_ADD_DRIVER
ifeq ($$($1),y)
WIFI_DRIVER_SELECTED += $2
WIFI_DRIVER_INTERFACE := $3
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
WIFI_DRIVER_INTERFACE := $(strip $(WIFI_DRIVER_INTERFACE))

ifeq ($(WIFI_DRIVER_SELECTED),)
$(error No Thingino Wi-Fi driver (BR2_PACKAGE_WIFI_*) selected)
endif
ifneq ($(words $(WIFI_DRIVER_SELECTED)),1)
$(error Multiple Thingino Wi-Fi drivers selected: $(WIFI_DRIVER_SELECTED))
endif

WLAN_MODULE := $(firstword $(WIFI_DRIVER_SELECTED))
WIFI_INTERFACE := $(if $(WIFI_DRIVER_INTERFACE),$(WIFI_DRIVER_INTERFACE),unknown)

ifeq ($(WIFI_INTERFACE),sdio)
WIFI_MODULE_IS_SDIO_FLAG := 1
else
WIFI_MODULE_IS_SDIO_FLAG := 0
endif

ifeq ($(WLAN_MODULE),hi3881)
WIFI_IS_HI3881_FLAG := 1
else
WIFI_IS_HI3881_FLAG := 0
endif

WIFI_SDIO_SET_GPIO_FLAG := 0
WIFI_SDIO_RETURN_EARLY_FLAG := 0
WIFI_SDIO_UNSUPPORTED_FLAG := 0

ifeq ($(WIFI_INTERFACE),sdio)
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
	--var SOC_FAMILY=$(SOC_FAMILY) \
	--var SOC_MODEL=$(SOC_MODEL) \
	--var WIFI_MODULE_IS_SDIO=$(WIFI_MODULE_IS_SDIO_FLAG) \
	--var WIFI_INTERFACE=$(WIFI_INTERFACE) \
	--var WIFI_SDIO_SET_GPIO=$(WIFI_SDIO_SET_GPIO_FLAG) \
	--var WIFI_SDIO_RETURN_EARLY=$(WIFI_SDIO_RETURN_EARLY_FLAG) \
	--var WIFI_SDIO_UNSUPPORTED=$(WIFI_SDIO_UNSUPPORTED_FLAG) \
	--var WIFI_IS_HI3881=$(WIFI_IS_HI3881_FLAG)

define WIFI_LINUX_CONFIG_FIXUPS
	$(call KCONFIG_SET_OPT,CONFIG_RFKILL,y)
endef

define WIFI_INSTALL_TARGET_CMDS
	$(INSTALL) -d $(TARGET_DIR)/etc/init.d
	$(WIFI_TEMPLATE_PYTHON) $(WIFI_TEMPLATE_RENDERER) --template $(WIFI_PKGDIR)/files/S36wireless.in \
		--output $(TARGET_DIR)/etc/init.d/S36wireless $(WIFI_TEMPLATE_VARS)
	chmod 0755 $(TARGET_DIR)/etc/init.d/S36wireless

	$(INSTALL) -D -m 0755 $(WIFI_PKGDIR)/files/S38wpa_supplicant \
		$(TARGET_DIR)/etc/init.d/S38wpa_supplicant

	$(INSTALL) -D -m 0755 $(WIFI_PKGDIR)/files/wlan \
		$(TARGET_DIR)/usr/sbin/wlan

	ln -sr $(TARGET_DIR)/usr/sbin/wlan $(TARGET_DIR)/usr/sbin/wlancli
	ln -sr $(TARGET_DIR)/usr/sbin/wlan $(TARGET_DIR)/usr/sbin/wlaninfo
	ln -sr $(TARGET_DIR)/usr/sbin/wlan $(TARGET_DIR)/usr/sbin/wlanreset
	ln -sr $(TARGET_DIR)/usr/sbin/wlan $(TARGET_DIR)/usr/sbin/wlanrssi
	ln -sr $(TARGET_DIR)/usr/sbin/wlan $(TARGET_DIR)/usr/sbin/wlansetup
	ln -sr $(TARGET_DIR)/usr/sbin/wlan $(TARGET_DIR)/usr/sbin/wlantemp

	$(INSTALL) -D -m 0644 $(WIFI_PKGDIR)/files/wlan0 \
		$(TARGET_DIR)/etc/network/interfaces.d/wlan0

	if [ "$(BR2_PACKAGE_THINGINO_KOPT_MMC1_PA_4BIT)" = "y" ]; then \
		$(INSTALL) -D -m 0755 $(WIFI_PKGDIR)/files/mmc_gpio_pa \
			$(TARGET_DIR)/usr/sbin/mmc_gpio ; \
	else \
		$(INSTALL) -D -m 0755 $(WIFI_PKGDIR)/files/mmc_gpio_pb \
			$(TARGET_DIR)/usr/sbin/mmc_gpio ; \
	fi
endef

$(eval $(generic-package))
