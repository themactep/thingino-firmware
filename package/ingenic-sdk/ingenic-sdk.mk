INGENIC_SDK_SITE_METHOD = git
INGENIC_SDK_SITE = https://github.com/themactep/ingenic-sdk
INGENIC_SDK_SITE_BRANCH = master
INGENIC_SDK_VERSION = 77f3a5784873718e6222c8f49b706a9149c7b792

INGENIC_SDK_LICENSE = GPL-3.0
INGENIC_SDK_LICENSE_FILES = LICENSE

INGENIC_SDK_MODULE_MAKE_OPTS = \
	SOC_FAMILY=$(SOC_FAMILY) \
	KERNEL_VERSION=$(KERNEL_VERSION) \
	INSTALL_MOD_PATH=$(TARGET_DIR) \
	INSTALL_MOD_DIR=ingenic \
	SENSOR_1_MODEL=$(SENSOR_1_MODEL) \
	$(MULTI_SENSOR_ENABLED) \
	$(MULTI_SENSOR_1_ENABLED) \
	$(MULTI_SENSOR_2_ENABLED)

ifeq ($(KERNEL_VERSION),3.10)
INGENIC_SDK_MODULE_MAKE_OPTS += EXTRA_CFLAGS=-DCONFIG_KERNEL_3_10
else
INGENIC_SDK_MODULE_MAKE_OPTS += EXTRA_CFLAGS=-DCONFIG_KERNEL_4_4_94
endif

# Old SDK's don't set the SOC in the IQ file name
ifneq ($(SENSOR_1_MODEL),)
	ifeq ($(BR2_SOC_INGENIC_T10)$(BR2_SOC_INGENIC_T20)$(BR2_SOC_INGENIC_T30),y)
		SENSOR_1_CONFIG_NAME = $(SENSOR_1_MODEL).bin
	else
		SENSOR_1_CONFIG_NAME = $(SENSOR_1_MODEL)-$(SOC_FAMILY).bin
	endif

	ifneq ($(BR2_THINGINO_IMAGE_SENSOR_QTY),1)
		MULTI_SENSOR_ENABLED   = CONFIG_MULTI_SENSOR=1
		SENSOR_1_CONFIG_NAME   = $(patsubst %s0,%,$(SENSOR_1_MODEL))-$(SOC_FAMILY).bin
		SENSOR_1_BIN_NAME      = $(patsubst %s0,%,$(SENSOR_1_MODEL))
		MULTI_SENSOR_1_ENABLED = SENSOR_1_MODEL=$(SENSOR_1_MODEL)
		MULTI_SENSOR_2_ENABLED = SENSOR_2_MODEL=$(SENSOR_2_MODEL)
		SENSOR_2_CONFIG_NAME   = $(SENSOR_2_MODEL)-$(SOC_FAMILY).bin
	else
		MULTI_SENSOR_ENABLED =
		SENSOR_1_BIN_NAME = $(SENSOR_1_MODEL)
	endif
endif

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

define INSTALL_SENSOR_BIN
	if [ "$(1)" != "" ]; then \
		$(if $(filter-out $(SENSOR_2_MODEL),$(1)),ln -sf /usr/share/sensor $(TARGET_DIR)/etc/sensor;) \
		$(INSTALL) -D -m 0644 $(@D)/sensor-iq/$(SOC_FAMILY)/$(2).bin \
			$(TARGET_DIR)/usr/share/sensor/$(3); \
		if [ -f $(@D)/sensor-iq/$(SOC_FAMILY)/$(2)-cust.bin ]; then \
			$(INSTALL) -D -m 0644 $(@D)/sensor-iq/$(SOC_FAMILY)/$(2)-cust.bin \
				$(TARGET_DIR)/usr/share/sensor/$(patsubst %.bin,$(2)-cust-$(SOC_FAMILY).bin,$(3)); \
		fi; \
		$(if $(filter-out $(SENSOR_2_MODEL),$(1)),echo $(1) > $(TARGET_DIR)/usr/share/sensor/model;) \
	fi
endef

define GENERATE_MODULE_LOADER
	$(INSTALL) -m 0755 -d $(TARGET_DIR)/etc/modules.d

	if [ "$(BR2_THINGINO_AIP)" = "y" ]; then \
		echo "ingenic-aip" > $(TARGET_DIR)/etc/modules.d/aip; \
	fi

	if [ "$(BR2_THINGINO_VIDEO_OUT)" = "y" ]; then \
		echo "vde" > $(TARGET_DIR)/etc/modules.d/vde; \
		echo "fb" > $(TARGET_DIR)/etc/modules.d/fb; \
		echo "ipu $(IPU_CLK_SRC) $(IPU_CLK)" > $(TARGET_DIR)/etc/modules.d/ipu; \
	fi

	if [ "$(BR2_THINGINO_VDEC)" = "y" ]; then \
		echo "vdec" > $(TARGET_DIR)/etc/modules.d/vdec; \
	fi

	if [ "$(BR2_THINGINO_HDMI_AUDIO)" = "y" ]; then \
		echo "hdmi_audio" > $(TARGET_DIR)/etc/modules.d/hdmi_audio; \
	fi

	if [ "$(SOC_FAMILY)" != "a1" ]; then \
		if [ "$(SOC_FAMILY)" = "t23" ]; then \
			echo tx_isp_$(SOC_FAMILY) $(ISP_CLK_SRC) $(ISP_CLK) $(ISP_CLKA_CLK_SRC) $(ISP_CLKA_CLK) $(ISP_DAY_NIGHT_SWITCH_DROP_FRAME_NUM) $(ISP_CH0_PRE_DEQUEUE_TIME) $(ISP_CH0_PRE_DEQUEUE_INTERRUPT_PROCESS) $(ISP_CH0_PRE_DEQUEUE_VALID_LINES) $(ISP_CH1_DEQUEUE_DELAY_TIME) $(ISP_MIPI_SWITCH_GPIO) $(ISP_DIRECT_MODE) $(ISP_IVDC_MEM_LINE) $(ISP_IVDC_THRESHOLD_LINE) $(ISP_CONFIG_HZ) $(ISP_MEMOPT) $(ISP_PRINT_LEVEL) $(BR2_ISP_PARAMS) > $(TARGET_DIR)/etc/modules.d/isp; \
		elif [ "$(SOC_FAMILY)" = "t30" ]; then \
			echo tx_isp_$(SOC_FAMILY) $(ISP_CLK) $(ISP_PRINT_LEVEL) $(ISP_ISPW) $(ISP_ISPH) $(ISP_ISPTOP) $(ISP_ISPLEFT) $(ISP_ISPCROP) $(ISP_ISPCROPWH) $(ISP_ISPCROPTL) $(ISP_ISPSCALER) $(ISP_ISPSCALERWH) $(ISP_ISP_M1_BUFS) $(ISP_ISP_M2_BUFS) $(BR2_ISP_PARAMS) > $(TARGET_DIR)/etc/modules.d/isp; \
		elif [ "$(SOC_FAMILY)" = "t41" ]; then \
			echo tx_isp_$(SOC_FAMILY) $(ISP_CLK_SRC) $(ISP_CLK) $(ISP_CLKA_CLK_SRC) $(ISP_CLKA_CLK) $(ISP_CLKS_CLK_SRC) $(ISP_CLKS_CLK) $(ISP_DIRECT_MODE) $(ISP_MEMOPT) $(BR2_ISP_PARAMS) > $(TARGET_DIR)/etc/modules.d/isp; \
		else \
			echo tx_isp_$(SOC_FAMILY) $(ISP_CLK) $(ISP_DAY_NIGHT_SWITCH_DROP_FRAME_NUM) $(ISP_CH0_PRE_DEQUEUE_TIME) $(ISP_CH0_PRE_DEQUEUE_INTERRUPT_PROCESS) $(ISP_CH0_PRE_DEQUEUE_VALID_LINES) $(ISP_CH1_DEQUEUE_DELAY_TIME) $(ISP_MEMOPT) $(ISP_PRINT_LEVEL) $(BR2_ISP_PARAMS) > $(TARGET_DIR)/etc/modules.d/isp; \
		fi \
	fi

	if [ "$(SOC_FAMILY)" = "t31" ] || [ "$(SOC_FAMILY)" = "c100" ] || [ "$(SOC_FAMILY)" = "t40" ] || [ "$(SOC_FAMILY)" = "t41" ]; then \
		echo "avpu $(AVPU_CLK_SRC) $(AVPU_CLK)" > $(TARGET_DIR)/etc/modules.d/avpu; \
	fi

	if [ "$(BR2_THINGINO_PWM_ENABLE)" = "y" ]; then \
		echo "pwm_core tcu_channels=0,1,3" >> $(TARGET_DIR)/etc/modules.d/pwm; \
		echo "pwm_hal" >> $(TARGET_DIR)/etc/modules.d/pwm; \
	fi

	if [ "$(SOC_FAMILY)" = "t40" ] || [ "$(SOC_FAMILY)" = "t41" ]; then \
		echo "mpsys-driver" >> $(TARGET_DIR)/etc/modules.d/mpsys; \
	fi

	if [ "$(BR2_THINGINO_NNA)" = "y" ] || [ "$(SOC_FAMILY)" = "t40" ] || [ "$(SOC_FAMILY)" = "t41" ]; then \
		echo "soc-nna" >> $(TARGET_DIR)/etc/modules.d/nna; \
	fi

	if [ -n "$(SENSOR_1_MODEL)" ]; then \
		if [ -n "$(SENSOR_2_MODEL)" ]; then \
			echo "sensor_$(SENSOR_1_MODEL)_$(SOC_FAMILY) $(BR2_SENSOR_1_PARAMS)" > $(TARGET_DIR)/etc/modules.d/sensor_1; \
		else \
			echo "sensor_$(SENSOR_1_MODEL)_$(SOC_FAMILY) $(BR2_SENSOR_1_PARAMS)" > $(TARGET_DIR)/etc/modules.d/sensor; \
		fi; \
	fi

	if [ -n "$(SENSOR_2_MODEL)" ]; then \
		echo "sensor_$(SENSOR_2_MODEL)_$(SOC_FAMILY) $(BR2_SENSOR_2_PARAMS)" > $(TARGET_DIR)/etc/modules.d/sensor_2; \
	fi
endef

define INSTALL_AUDIO_SUPPORT
	gpio_speaker=$(BR2_THINGINO_AUDIO_GPIO); \
	if [ -z "$$gpio_speaker" ]; then \
		spk_gpio=-1; \
		spk_level=-1; \
	else \
		spk_gpio=$$gpio_speaker; \
		if [ "$(BR2_THINGINO_AUDIO_GPIO_LOW)" = "y" ]; then \
			spk_level=0; \
		else \
			spk_level=1; \
		fi; \
	fi; \
	echo "audio spk_gpio=$$spk_gpio spk_level=$$spk_level $(BR2_THINGINO_AUDIO_PARAMS)" > $(TARGET_DIR)/etc/modules.d/audio

	[ -f $(@D)/config/webrtc_profile.ini ] && $(INSTALL) -D -m 0644 $(@D)/config/webrtc_profile.ini $(TARGET_DIR)/etc/

	$(INSTALL) -D -m 0755 $(INGENIC_SDK_PKGDIR)/files/speaker-ctrl $(TARGET_DIR)/usr/sbin/speaker-ctrl
endef

define INGENIC_SDK_INSTALL_TARGET_CMDS
	$(INSTALL) -m 0755 -d $(TARGET_MODULES_PATH)
	touch $(TARGET_MODULES_PATH)/modules.builtin.modinfo

	if [ -n "$(SENSOR_1_MODEL)" ]; then \
		$(call INSTALL_SENSOR_BIN,$(SENSOR_1_MODEL),$(SENSOR_1_BIN_NAME),$(SENSOR_1_CONFIG_NAME)); \
		$(call INSTALL_SENSOR_BIN,$(SENSOR_2_MODEL),$(SENSOR_2_BIN_NAME),$(SENSOR_2_CONFIG_NAME)); \
	fi

	$(GENERATE_MODULE_LOADER)
	$(GENERATE_GPIO_USERKEYS_CONFIG)
	[ "$(BR2_THINGINO_AUDIO)" = "y" ] && $(INSTALL_AUDIO_SUPPORT)
endef

$(eval $(kernel-module))
$(eval $(generic-package))

