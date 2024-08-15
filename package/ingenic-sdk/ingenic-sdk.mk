INGENIC_SDK_SITE_METHOD = git
INGENIC_SDK_SITE = https://github.com/themactep/ingenic-sdk
INGENIC_SDK_SITE_BRANCH = master
INGENIC_SDK_VERSION = $(shell git ls-remote $(INGENIC_SDK_SITE) $(INGENIC_SDK_SITE_BRANCH) | head -1 | cut -f1)

INGENIC_SDK_LICENSE = GPL-3.0
INGENIC_SDK_LICENSE_FILES = LICENSE

INGENIC_SDK_MODULE_MAKE_OPTS = \
	SOC_FAMILY=$(SOC_FAMILY) \
	SENSOR_MODEL=$(SENSOR_MODEL) \
	KERNEL_VERSION=$(KERNEL_VERSION) \
	INSTALL_MOD_PATH=$(TARGET_DIR) \
	INSTALL_MOD_DIR=ingenic

LINUX_CONFIG_LOCALVERSION = \
	$(shell awk -F "=" '/^CONFIG_LOCALVERSION=/ {print $$2}' $(BR2_LINUX_KERNEL_CUSTOM_CONFIG_FILE))

ifeq ($(BR2_SOC_INGENIC_T10)$(BR2_SOC_INGENIC_T20)$(BR2_SOC_INGENIC_T30),y)
SENSOR_CONFIG_NAME = $(SENSOR_MODEL).bin
else
SENSOR_CONFIG_NAME = $(SENSOR_MODEL)-$(SOC_FAMILY).bin
endif

ifeq ($(KERNEL_VERSION_4),y)
FULL_KERNEL_VERSION = 4.4.94
else
FULL_KERNEL_VERSION = 3.10.14
endif

TARGET_MODULES_PATH = $(TARGET_DIR)/lib/modules/$(FULL_KERNEL_VERSION)$(call qstrip,$(LINUX_CONFIG_LOCALVERSION))

define GENERATE_GPIO_USERKEYS_CONFIG
	gpio_userkeys_config="gpio-userkeys gpio_config="; \
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
		echo "$$gpio_userkeys_config" > $(TARGET_DIR)/etc/modules.d/gpio-userkeys; \
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
		echo "audio spk_gpio=$$spk_gpio spk_level=$$spk_level $(BR2_AUDIO_PARAMS)" > $(TARGET_DIR)/etc/modules.d/audio; \
	else \
		echo "Skipping audio configuration: U_BOOT_ENV_TXT is empty or does not exist."; \
	fi
endef

define INGENIC_SDK_INSTALL_TARGET_CMDS
	$(INSTALL) -m 755 -d $(TARGET_MODULES_PATH)
	touch $(TARGET_MODULES_PATH)/modules.builtin.modinfo

	$(INSTALL) -m 755 -d $(TARGET_DIR)/etc/sensor
	$(INSTALL) -m 644 -D $(@D)/sensor-iq/$(SOC_FAMILY)/$(SENSOR_MODEL).bin $(TARGET_DIR)/etc/sensor/$(SENSOR_CONFIG_NAME)
	echo $(SENSOR_MODEL) > $(TARGET_DIR)/etc/sensor/model

	$(INSTALL) -m 755 -d $(TARGET_DIR)/etc/modules.d

	if [ "$(SOC_FAMILY)" = "t23" ]; then \
		echo tx_isp_$(SOC_FAMILY) $(ISP_CLK_SRC) isp_clk=$(ISP_CLK) $(ISP_CLKA_CLK_SRC) isp_clka=$(ISP_CLKA_CLK) $(ISP_MEMOPT) $(BR2_ISP_PARAMS) > $(TARGET_DIR)/etc/modules.d/isp; \
	else \
		echo tx_isp_$(SOC_FAMILY) isp_clk=$(ISP_CLK) $(ISP_MEMOPT) $(BR2_ISP_PARAMS) > $(TARGET_DIR)/etc/modules.d/isp; \
	fi

	if [ "$(SOC_FAMILY)" = "t31" ]; then \
		echo "avpu $(AVPU_CLK_SRC) avpu_clk=$(AVPU_CLK)" > $(TARGET_DIR)/etc/modules.d/avpu; \
	fi

	if [ "$(BR2_AUDIO)" = "y" ]; then \
		$(INSTALL) -m 644 -D $(@D)/config/webrtc_profile.ini $(TARGET_DIR)/etc/; \
		$(GENERATE_AUDIO_CONFIG); \
	fi

	if [ "$(BR2_PWM_ENABLE)" = "y" ]; then \
		echo "pwm_core" >> $(TARGET_DIR)/etc/modules.d/pwm; \
		echo "pwm_hal" >> $(TARGET_DIR)/etc/modules.d/pwm; \
	fi

	echo "sensor_$(SENSOR_MODEL)_$(SOC_FAMILY) $(BR2_SENSOR_PARAMS)" > $(TARGET_DIR)/etc/modules.d/sensor; \

	$(GENERATE_GPIO_USERKEYS_CONFIG)
endef

$(eval $(kernel-module))
$(eval $(generic-package))
