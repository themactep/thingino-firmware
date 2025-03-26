INGENIC_SDK_SITE_METHOD = git
INGENIC_SDK_SITE = https://github.com/themactep/ingenic-sdk
INGENIC_SDK_SITE_BRANCH = master
INGENIC_SDK_VERSION = $(shell git ls-remote $(INGENIC_SDK_SITE) $(INGENIC_SDK_SITE_BRANCH) | head -1 | cut -f1)

INGENIC_SDK_LICENSE = GPL-3.0
INGENIC_SDK_LICENSE_FILES = LICENSE

ifeq ($(BR2_SOC_INGENIC_T10)$(BR2_SOC_INGENIC_T20)$(BR2_SOC_INGENIC_T30),y)
	SENSOR_CONFIG_NAME = $(SENSOR_MODEL).bin
else
	SENSOR_CONFIG_NAME = $(SENSOR_MODEL)-$(SOC_FAMILY).bin
endif

ifneq ($(BR2_THINGINO_IMAGE_SENSOR_QTY_2)$(BR2_THINGINO_IMAGE_SENSOR_QTY_3)$(BR2_THINGINO_IMAGE_SENSOR_QTY_4),)
	MULTI_SENSOR_ENABLED = CONFIG_MULTI_SENSOR=1
	SENSOR_CONFIG_NAME = $(patsubst %s0,%,$(SENSOR_MODEL_1))-$(SOC_FAMILY).bin
	SENSOR_1_BIN_NAME = $(patsubst %s0,%,$(SENSOR_MODEL_1))
	MULTI_SENSOR_1_ENABLED = SENSOR_MODEL_1=$(SENSOR_MODEL_1)
	MULTI_SENSOR_2_ENABLED = SENSOR_MODEL_2=$(SENSOR_MODEL_2)
	SENSOR_2_CONFIG_NAME = $(SENSOR_MODEL_2)-$(SOC_FAMILY).bin
else
	MULTI_SENSOR_ENABLED =
endif


INGENIC_SDK_MODULE_MAKE_OPTS = \
	SOC_FAMILY=$(SOC_FAMILY) \
	KERNEL_VERSION=$(KERNEL_VERSION) \
	INSTALL_MOD_PATH=$(TARGET_DIR) \
	INSTALL_MOD_DIR=ingenic \
	SENSOR_MODEL=$(SENSOR_MODEL) \
	$(MULTI_SENSOR_ENABLED) \
	$(MULTI_SENSOR_1_ENABLED) \
	$(MULTI_SENSOR_2_ENABLED)


LINUX_CONFIG_LOCALVERSION = \
	$(shell awk -F "=" '/^CONFIG_LOCALVERSION=/ {print $$2}' $(BR2_LINUX_KERNEL_CUSTOM_CONFIG_FILE))

ifeq ($(KERNEL_VERSION_4),y)
	FULL_KERNEL_VERSION = 4.4.94
else
	FULL_KERNEL_VERSION = 3.10.14
endif

TARGET_MODULES_PATH = $(TARGET_DIR)/lib/modules/$(FULL_KERNEL_VERSION)$(call qstrip,$(LINUX_CONFIG_LOCALVERSION))

define GENERATE_GPIO_USERKEYS_CONFIG
	gpio_userkeys_config="gpio-userkeys gpio_config="\"; \
	keycode=2; \
	first_button=28; \
	has_gpio_buttons=0; \
	while IFS= read -r line; do \
		case "$$line" in \
			gpio_button=*) \
				has_gpio_buttons=1; \
				gpio_num=$${line#*=}; \
				gpio_num=$$(echo $$gpio_num | tr -cd '[0-9]'); \
				gpio_userkeys_config="$$gpio_userkeys_config$${first_button},$${gpio_num},1;"; \
				;; \
			gpio_button_*=*) \
				has_gpio_buttons=1; \
				gpio_num=$${line#*=}; \
				gpio_num=$$(echo $$gpio_num | tr -cd '[0-9]'); \
				gpio_userkeys_config="$$gpio_userkeys_config$${keycode},$${gpio_num},1;"; \
				keycode=$$((keycode + 1)); \
				;; \
		esac; \
	done < $(U_BOOT_ENV_TXT); \
	if [ "$$has_gpio_buttons" -eq 1 ]; then \
		gpio_userkeys_config=$${gpio_userkeys_config%;}; \
		echo "$$gpio_userkeys_config\"" > $(TARGET_DIR)/etc/modules.d/gpio-userkeys; \
	fi
endef

define GENERATE_AUDIO_CONFIG
	if [ -n "$(U_BOOT_ENV_TXT)" ] && [ -f $(U_BOOT_ENV_TXT) ]; then \
		gpio_speaker=$$(awk -F= '/^gpio_speaker=/ {print $$2}' $(U_BOOT_ENV_TXT)); \
		if [ -z "$$gpio_speaker" ]; then \
				spk_gpio=-1; \
				spk_level=-1; \
		elif echo "$$gpio_speaker" | grep -qE '^[0-9]+[Oo]$$'; then \
				spk_gpio=$$(echo "$$gpio_speaker" | sed 's/[Oo]$$//'); \
				spk_level=$$(echo "$$gpio_speaker" | grep -q 'O$$' && echo 1 || echo 0); \
		else \
				spk_gpio=$$gpio_speaker; \
				spk_level=-1; \
		fi; \
		echo "audio spk_gpio=$$spk_gpio spk_level=$$spk_level $(BR2_THINGINO_AUDIO_PARAMS)" > $(TARGET_DIR)/etc/modules.d/audio; \
	else \
		echo "Skipping audio configuration: U_BOOT_ENV_TXT is empty or does not exist."; \
	fi
endef

define install_sensor_bin
	if [ "$(1)" != "" ]; then \
		$(if $(filter-out $(SENSOR_MODEL_2),$(1)),ln -sf /usr/share/sensor $(TARGET_DIR)/etc/sensor;) \
		$(INSTALL) -m 755 -d $(TARGET_DIR)/usr/share/sensor; \
		if [ "$(SOC_FAMILY)" = "t23" ]; then \
			$(INSTALL) -m 644 -D $(@D)/sensor-iq/$(SOC_FAMILY)/1.1.2/$(2).bin $(TARGET_DIR)/usr/share/sensor/$(3); \
		else \
			$(INSTALL) -m 644 -D $(@D)/sensor-iq/$(SOC_FAMILY)/$(2).bin $(TARGET_DIR)/usr/share/sensor/$(3); \
		fi; \
		$(if $(filter-out $(SENSOR_MODEL_2),$(1)),echo $(1) > $(TARGET_DIR)/usr/share/sensor/model;) \
	fi
endef

define INGENIC_SDK_INSTALL_TARGET_CMDS
	$(INSTALL) -m 755 -d $(TARGET_MODULES_PATH)
	touch $(TARGET_MODULES_PATH)/modules.builtin.modinfo

	$(call install_sensor_bin,$(SENSOR_MODEL),$(SENSOR_MODEL),$(SENSOR_CONFIG_NAME))
	$(call install_sensor_bin,$(SENSOR_MODEL_1),$(SENSOR_1_BIN_NAME),$(SENSOR_CONFIG_NAME))
	$(call install_sensor_bin,$(SENSOR_MODEL_2),$(SENSOR_1_BIN_NAME),$(SENSOR_2_CONFIG_NAME))

	$(INSTALL) -m 755 -d $(TARGET_DIR)/etc/modules.d

	if [ "$(SOC_FAMILY)" = "t23" ]; then \
		echo tx_isp_$(SOC_FAMILY) $(ISP_CLK_SRC) isp_clk=$(ISP_CLK) $(ISP_CLKA_CLK_SRC) isp_clka=$(ISP_CLKA_CLK) $(ISP_MEMOPT) $(BR2_ISP_PARAMS) > $(TARGET_DIR)/etc/modules.d/isp; \
	else \
		echo tx_isp_$(SOC_FAMILY) isp_clk=$(ISP_CLK) $(ISP_MEMOPT) $(BR2_ISP_PARAMS) > $(TARGET_DIR)/etc/modules.d/isp; \
	fi

	if [ "$(SOC_FAMILY)" = "t31" ] || [ "$(SOC_FAMILY)" = "t40" ] || [ "$(SOC_FAMILY)" = "t41" ]; then \
		echo "avpu $(AVPU_CLK_SRC) avpu_clk=$(AVPU_CLK)" > $(TARGET_DIR)/etc/modules.d/avpu; \
	fi

	if [ "$(BR2_THINGINO_AUDIO)" = "y" ]; then \
		$(INSTALL) -m 644 -D $(@D)/config/webrtc_profile.ini $(TARGET_DIR)/etc/; \
		$(GENERATE_AUDIO_CONFIG); \
		$(INSTALL) -m 755 -d $(TARGET_DIR)/usr/sbin; \
		$(INSTALL) -m 755 -D $(INGENIC_SDK_PKGDIR)/files/speaker-ctrl $(TARGET_DIR)/usr/sbin/speaker-ctrl; \
	fi

	if [ "$(BR2_THINGINO_PWM_ENABLE)" = "y" ]; then \
		echo "pwm_core" >> $(TARGET_DIR)/etc/modules.d/pwm; \
		echo "pwm_hal" >> $(TARGET_DIR)/etc/modules.d/pwm; \
	fi

	if [ "$(SENSOR_MODEL)" != "" ]; then \
		echo "sensor_$(SENSOR_MODEL)_$(SOC_FAMILY) $(BR2_SENSOR_PARAMS)" > $(TARGET_DIR)/etc/modules.d/sensor; \
	fi

	if [ "$(SENSOR_MODEL_1)" != "" ]; then \
		echo "sensor_$(SENSOR_MODEL_1)_$(SOC_FAMILY) $(BR2_SENSOR_1_PARAMS)" > $(TARGET_DIR)/etc/modules.d/sensor_1; \
	fi

	if [ "$(SENSOR_MODEL_2)" != "" ]; then \
		echo "sensor_$(SENSOR_MODEL_2)_$(SOC_FAMILY) $(BR2_SENSOR_2_PARAMS)" > $(TARGET_DIR)/etc/modules.d/sensor_2; \
	fi

	$(GENERATE_GPIO_USERKEYS_CONFIG)
endef

$(eval $(kernel-module))
$(eval $(generic-package))
