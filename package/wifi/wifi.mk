WIFI_SITE_METHOD = local
WIFI_SITE = $(BR2_EXTERNAL)/package/wifi

WIFI_DEPENDENCIES += host-python3

WIFI_TEMPLATE_RENDERER = $(BR2_EXTERNAL)/scripts/render_template.py
WIFI_TEMPLATE_PYTHON = $(HOST_DIR)/bin/python3

WIFI_CAMERA_DIR = $(BR2_EXTERNAL)/$(CAMERA_SUBDIR)/$(CAMERA)
WIFI_RUNTIME_CONFIG = $(WIFI_CAMERA_DIR)/$(CAMERA).config

ifeq ($(wildcard $(WIFI_RUNTIME_CONFIG)),)
$(error Wi-Fi runtime config not found: $(WIFI_RUNTIME_CONFIG))
endif

WLAN_MODULE = $(strip $(shell awk -F= '/^wlan_module=/ {gsub(/"/,"",$$2); print $$2; exit}' $(WIFI_RUNTIME_CONFIG)))

ifeq ($(WLAN_MODULE),)
$(error wlan_module is not set in $(WIFI_RUNTIME_CONFIG))
endif

WIFI_SDIO_MODULES := 8189es 8189fs atbm6031 atbm6031x b43 bcmdhd hi3881 ssv6158
WIFI_MODULE_IS_SDIO := $(filter $(WLAN_MODULE),$(WIFI_SDIO_MODULES))

ifeq ($(WIFI_MODULE_IS_SDIO),)
WIFI_MODULE_IS_SDIO_FLAG := 0
else
WIFI_MODULE_IS_SDIO_FLAG := 1
endif

ifeq ($(WLAN_MODULE),hi3881)
WIFI_IS_HI3881_FLAG := 1
else
WIFI_IS_HI3881_FLAG := 0
endif

WIFI_SDIO_SET_GPIO_FLAG := 0
WIFI_SDIO_RETURN_EARLY_FLAG := 0
WIFI_SDIO_UNSUPPORTED_FLAG := 0

ifneq ($(WIFI_MODULE_IS_SDIO),)
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
