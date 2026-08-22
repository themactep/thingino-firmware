INGENIC_SDK_SITE_METHOD = git
INGENIC_SDK_SITE = https://github.com/thingino/ingenic-sdk
INGENIC_SDK_SITE_BRANCH = main
INGENIC_SDK_VERSION = 8ac092f6c37a0423a1d904a480c9fd327f19480d

INGENIC_SDK_LICENSE = GPL-2.0+
INGENIC_SDK_LICENSE_FILES = LICENSE

# Ensure thingino-core is installed before ingenic-sdk so thingino.json is available
INGENIC_SDK_DEPENDENCIES = thingino-core host-thingino-jct

# Optional ISP firmware version for sensor IQ selection. When set, IQ tuning is
# taken from sensor-iq/<soc>/<version>/ (e.g. t23 2.10) instead of the flat
# per-soc default. Empty selects the primary version.
SENSOR_ISP_FW = $(call qstrip,$(BR2_SENSOR_ISP_FW))

# Map thingino's config onto the SDK's own CONFIG_INGENIC_* component
# switches, driven by the "SDK components" menu in this package's Config.in.
# The SDK no longer reads BR2_* symbols itself.
#
# Each mapping forces an explicit y/n so the menu is authoritative: the
# Config.in default already carries the SoC/kernel-correct value, and an
# override there wins. Audio follows the top-level BR2_THINGINO_AUDIO
# switch rather than a component-menu entry.
INGENIC_SDK_COMPONENTS = \
	CONFIG_INGENIC_ISP=$(if $(BR2_THINGINO_DEV_CAMERA),y,n) \
	CONFIG_INGENIC_SENSOR=$(if $(BR2_THINGINO_DEV_CAMERA),y,n) \
	CONFIG_INGENIC_AUDIO=$(if $(BR2_THINGINO_AUDIO),y,n) \
	CONFIG_INGENIC_AVPU=$(if $(BR2_INGENIC_SDK_AVPU),y,n) \
	CONFIG_INGENIC_SOC_NNA=$(if $(BR2_INGENIC_SDK_SOC_NNA),y,n) \
	CONFIG_INGENIC_MPSYS=$(if $(BR2_INGENIC_SDK_MPSYS),y,n) \
	CONFIG_INGENIC_JZ_DTRNG=$(if $(BR2_INGENIC_SDK_MPSYS),y,n) \
	CONFIG_INGENIC_GPIO_USERKEYS=$(if $(BR2_INGENIC_SDK_GPIO_USERKEYS),y,n) \
	CONFIG_INGENIC_JZ_AES=$(if $(BR2_INGENIC_SDK_JZ_AES),y,n) \
	CONFIG_INGENIC_TCU_ALLOC=$(if $(BR2_INGENIC_SDK_TCU_ALLOC),y,n) \
	CONFIG_INGENIC_PWM=$(if $(BR2_INGENIC_SDK_PWM),y,n) \
	CONFIG_INGENIC_MOTOR=$(if $(BR2_INGENIC_SDK_MOTOR),y,n)

INGENIC_SDK_MODULE_MAKE_OPTS = \
	SOC_FAMILY=$(SOC_FAMILY) \
	KERNEL_VERSION=$(KERNEL_VERSION) \
	INSTALL_MOD_PATH=$(TARGET_DIR) \
	INSTALL_MOD_DIR=ingenic \
	SENSOR_1_MODEL=$(SENSOR_1_MODEL) \
	$(INGENIC_SDK_COMPONENTS) \
	$(MULTI_SENSOR_ENABLED) \
	$(MULTI_SENSOR_1_ENABLED) \
	$(MULTI_SENSOR_2_ENABLED)

ifeq ($(KERNEL_VERSION),3.10.14)
INGENIC_SDK_EXTRA_CFLAGS = -DCONFIG_KERNEL_3_10
else
INGENIC_SDK_EXTRA_CFLAGS = -DCONFIG_KERNEL_4_4_94
endif

ifeq ($(BR2_MIPS_NAN_2008),y)
INGENIC_SDK_EXTRA_CFLAGS += -mnan=legacy
endif

ifeq ($(BR2_INGENIC_SDK_ISP_TRACE),y)
INGENIC_SDK_EXTRA_CFLAGS += -DCONFIG_JZ_ISP_TRACE
define INGENIC_SDK_LINUX_CONFIG_FIXUPS
	$(call KCONFIG_ENABLE_OPT,CONFIG_JZ_ISP_TRACE)
endef
endif

INGENIC_SDK_MODULE_MAKE_OPTS += EXTRA_CFLAGS="$(INGENIC_SDK_EXTRA_CFLAGS)"

# Per-camera IQ file overrides (paths relative to BR2_EXTERNAL root)
ifneq ($(call qstrip,$(BR2_SENSOR_1_IQ_FILE)),)
	SENSOR_1_IQ_OVERRIDE = $(BR2_EXTERNAL_THINGINO_PATH)/$(call qstrip,$(BR2_SENSOR_1_IQ_FILE))
endif
ifneq ($(call qstrip,$(BR2_SENSOR_2_IQ_FILE)),)
	SENSOR_2_IQ_OVERRIDE = $(BR2_EXTERNAL_THINGINO_PATH)/$(call qstrip,$(BR2_SENSOR_2_IQ_FILE))
endif

# Old SDK's don't set the SOC in the IQ file name
ifneq ($(SENSOR_1_MODEL),)
	ifneq ($(filter $(SOC_FAMILY),t10 t20 t30),)
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
		SENSOR_2_BIN_NAME      = $(patsubst %s1,%,$(SENSOR_2_MODEL))
		SENSOR_2_CONFIG_NAME   = $(patsubst %s1,%,$(SENSOR_2_MODEL))-$(SOC_FAMILY).bin
	else
		MULTI_SENSOR_ENABLED =
		SENSOR_1_BIN_NAME = $(SENSOR_1_MODEL)
	endif
endif

LINUX_CONFIG_LOCALVERSION = \
	$(shell awk -F "=" '/^CONFIG_LOCALVERSION=/ {print $$2}' $(BR2_LINUX_KERNEL_CUSTOM_CONFIG_FILE))

TARGET_MODULES_PATH = $(TARGET_DIR)/usr/lib/modules/$(KERNEL_VERSION)$(call qstrip,$(LINUX_CONFIG_LOCALVERSION))

# Use the host jct tool by absolute path, not a bare `which jct`: the
# host PATH is not guaranteed to carry it, and a silent miss here drops
# the button config with no error. host-thingino-jct is a build
# dependency (below) so the tool exists when this runs.
INGENIC_SDK_JCT = $(HOST_DIR)/bin/jct

# Board wiring is read from the camera's own config file, NOT from
# $(TARGET_DIR)/etc/thingino.json: thingino-core installs only
# configs/common.thingino.json to the target and stages the camera json as
# 90-camera.json, merging the two in a target-finalize hook that runs after
# every package has installed. With per-package directories a package
# therefore sees a thingino.json with no gpio section at all. This is also
# the file the U-Boot device-tree injectors in package/thingino-uboot read,
# so the kernel and the bootloader cannot end up driving different pins.
# Like those injectors, it does not see user/ layer overrides.
INGENIC_SDK_CAMERA_JSON = $(BR2_EXTERNAL_THINGINO_PATH)/$(CAMERA_SUBDIR)/$(CAMERA)/thingino.json

# Physical buttons come from gpio.button_reset and gpio.chime, accepted in
# the section's usual shapes: a bare pin number, or a {"pin": N, ...} object.
# The module wants KEYCODE,GPIO,ACTIVE_LOW triples joined by ";" (28 =
# KEY_ENTER for reset, 2 = KEY_1 for the chime), and appends them to the
# board's built-in button table.
#
# ACTIVE_LOW is fixed at 1 rather than read from the json. These are buttons
# that pull the pin to ground against a pull-up, which is why
# inject-uboot-mmc-dt.sh hardcodes GPIO_ACTIVE_LOW for this very same
# gpio.button_reset; the bare-int short notation would claim active-high and
# be wrong for every button in the fleet.
#
# Reads the camera config for the same reason INSTALL_AUDIO_SUPPORT does -
# $(TARGET_DIR)/etc/thingino.json holds nothing but common.thingino.json
# while this package installs, which is why this config had silently never
# been generated at all.
define GENERATE_GPIO_USERKEYS_CONFIG
	if [ "$(BR2_INGENIC_SDK_GPIO_USERKEYS)" = "y" ] && [ -r $(INGENIC_SDK_CAMERA_JSON) ]; then \
		if [ ! -x $(INGENIC_SDK_JCT) ]; then \
			echo "ERROR: host jct tool missing: $(INGENIC_SDK_JCT)"; exit 1; \
		fi; \
		gpio_userkeys_config=""; \
		for key_code in button_reset:28 chime:2; do \
			key=$${key_code%%:*}; \
			code=$${key_code##*:}; \
			pin=$$($(INGENIC_SDK_JCT) $(INGENIC_SDK_CAMERA_JSON) get gpio.$$key.pin 2>/dev/null); \
			if [ -z "$$pin" ]; then \
				pin=$$($(INGENIC_SDK_JCT) $(INGENIC_SDK_CAMERA_JSON) get gpio.$$key 2>/dev/null); \
			fi; \
			case "$$pin" in \
				"" | *[!0-9]*) continue ;; \
			esac; \
			gpio_userkeys_config="$${gpio_userkeys_config:+$$gpio_userkeys_config;}$$code,$$pin,1"; \
		done; \
		if [ -n "$$gpio_userkeys_config" ]; then \
			echo "gpio-userkeys gpio_config=\"$$gpio_userkeys_config\"" > $(TARGET_DIR)/etc/modules.d/05-gpio-userkeys; \
		fi; \
	fi
endef

# $(call INSTALL_SENSOR_BIN, model, bin_name, config_name, iq_override_path)
define INSTALL_SENSOR_BIN
	if [ "$(1)" != "" ] && [ "$(1)" != "none" ]; then \
		$(if $(filter-out $(SENSOR_2_MODEL),$(1)),ln -sf /usr/share/sensor $(TARGET_DIR)/etc/sensor;) \
		if [ -n "$(4)" ] && [ -f "$(4)" ]; then \
			$(INSTALL) -D -m 0644 $(4) \
				$(TARGET_DIR)/usr/share/sensor/$(3); \
		else \
			iqdir=$(@D)/sensor-iq/$(SOC_FAMILY); \
			if [ -n "$(SENSOR_ISP_FW)" ] && [ -f $$iqdir/$(SENSOR_ISP_FW)/$(2).bin ]; then \
				iqdir=$$iqdir/$(SENSOR_ISP_FW); \
			fi; \
			$(INSTALL) -D -m 0644 $$iqdir/$(2).bin \
				$(TARGET_DIR)/usr/share/sensor/$(3); \
			if [ -f $$iqdir/$(2)-cust.bin ]; then \
				$(INSTALL) -D -m 0644 $$iqdir/$(2)-cust.bin \
					$(TARGET_DIR)/usr/share/sensor/$(patsubst %.bin,$(2)-cust-$(SOC_FAMILY).bin,$(3)); \
			fi; \
		fi; \
		if [ "$(1)" != "$(2)" ]; then \
			ln -sf $(3) $(TARGET_DIR)/usr/share/sensor/$(1)-$(SOC_FAMILY).bin; \
		fi; \
		$(if $(filter-out $(SENSOR_2_MODEL),$(1)),echo $(1) > $(TARGET_DIR)/usr/share/sensor/model;) \
	fi
endef

define GENERATE_MODULE_LOADER
	$(INSTALL) -m 0755 -d $(TARGET_DIR)/etc/modules.d

	if [ "$(BR2_THINGINO_AIP)" = "y" ]; then \
		echo "ingenic-aip" > $(TARGET_DIR)/etc/modules.d/08-aip; \
	fi

	if [ "$(BR2_THINGINO_VIDEO_OUT)" = "y" ]; then \
		echo "vde" > $(TARGET_DIR)/etc/modules.d/21-vde; \
		echo "fb" > $(TARGET_DIR)/etc/modules.d/22-fb; \
		echo "ipu $(IPU_CLK_SRC) $(IPU_CLK)" > $(TARGET_DIR)/etc/modules.d/23-ipu; \
	fi

	if [ "$(BR2_THINGINO_VDEC)" = "y" ]; then \
		echo "vdec" > $(TARGET_DIR)/etc/modules.d/24-vdec; \
	fi

	if [ "$(BR2_THINGINO_HDMI_AUDIO)" = "y" ]; then \
		echo "hdmi_audio" > $(TARGET_DIR)/etc/modules.d/25-hdmi_audio; \
	fi

	if [ "$(BR2_THINGINO_DEV_CAMERA)" = "y" ] && [ "$(SOC_FAMILY)" != "a1" ]; then \
		if [ "$(SOC_FAMILY)" = "t23" ]; then \
			if [ "$(BR2_PACKAGE_OPEN_TX_ISP)" = "y" ]; then \
				echo tx_isp_$(SOC_FAMILY) $(ISP_CLK_SRC) $(ISP_CLK) $(ISP_CLKA_CLK_SRC) $(ISP_CLKA_CLK) $(ISP_DAY_NIGHT_SWITCH_DROP_FRAME_NUM) $(ISP_CH0_PRE_DEQUEUE_TIME) $(ISP_CH0_PRE_DEQUEUE_INTERRUPT_PROCESS) $(ISP_CH0_PRE_DEQUEUE_VALID_LINES) $(ISP_CH1_DEQUEUE_DELAY_TIME) $(ISP_DIRECT_MODE) $(ISP_IVDC_MEM_LINE) $(ISP_IVDC_THRESHOLD_LINE) $(ISP_MEMOPT) $(ISP_PRINT_LEVEL) $(BR2_ISP_PARAMS) > $(TARGET_DIR)/etc/modules.d/20-isp; \
			else \
				echo tx_isp_$(SOC_FAMILY) $(ISP_CLK_SRC) $(ISP_CLK) $(ISP_CLKA_CLK_SRC) $(ISP_CLKA_CLK) $(ISP_DAY_NIGHT_SWITCH_DROP_FRAME_NUM) $(ISP_CH0_PRE_DEQUEUE_TIME) $(ISP_CH0_PRE_DEQUEUE_INTERRUPT_PROCESS) $(ISP_CH0_PRE_DEQUEUE_VALID_LINES) $(ISP_CH1_DEQUEUE_DELAY_TIME) $(ISP_MIPI_SWITCH_GPIO) $(ISP_DIRECT_MODE) $(ISP_IVDC_MEM_LINE) $(ISP_IVDC_THRESHOLD_LINE) $(ISP_CONFIG_HZ) $(ISP_MEMOPT) $(ISP_PRINT_LEVEL) $(BR2_ISP_PARAMS) > $(TARGET_DIR)/etc/modules.d/20-isp; \
			fi; \
		elif [ "$(SOC_FAMILY)" = "t30" ]; then \
			echo tx_isp_$(SOC_FAMILY) $(ISP_CLK) $(ISP_PRINT_LEVEL) $(ISP_ISPW) $(ISP_ISPH) $(ISP_ISPTOP) $(ISP_ISPLEFT) $(ISP_ISPCROP) $(ISP_ISPCROPWH) $(ISP_ISPCROPTL) $(ISP_ISPSCALER) $(ISP_ISPSCALERWH) $(ISP_ISP_M1_BUFS) $(ISP_ISP_M2_BUFS) $(BR2_ISP_PARAMS) > $(TARGET_DIR)/etc/modules.d/20-isp; \
		elif [ "$(SOC_FAMILY)" = "t40" ] && [ "$(BR2_PACKAGE_OPEN_TX_ISP)" = "y" ]; then \
			echo tx_isp_$(SOC_FAMILY) $(ISP_CLK_SRC) $(ISP_CLK) $(ISP_CH0_PRE_DEQUEUE_TIME) $(ISP_MEMOPT) $(ISP_PRINT_LEVEL) $(BR2_ISP_PARAMS) > $(TARGET_DIR)/etc/modules.d/20-isp; \
		elif [ "$(SOC_FAMILY)" = "t41" ]; then \
			echo tx_isp_$(SOC_FAMILY) $(ISP_CLK_SRC) $(ISP_CLK) $(ISP_CLKA_CLK_SRC) $(ISP_CLKA_CLK) $(ISP_CLKS_CLK_SRC) $(ISP_CLKS_CLK) $(ISP_DIRECT_MODE) $(ISP_MEMOPT) $(BR2_ISP_PARAMS) > $(TARGET_DIR)/etc/modules.d/20-isp; \
		else \
			echo tx_isp_$(SOC_FAMILY) $(ISP_CLK) $(ISP_DAY_NIGHT_SWITCH_DROP_FRAME_NUM) $(ISP_CH0_PRE_DEQUEUE_TIME) $(ISP_CH0_PRE_DEQUEUE_INTERRUPT_PROCESS) $(ISP_CH0_PRE_DEQUEUE_VALID_LINES) $(ISP_CH1_DEQUEUE_DELAY_TIME) $(ISP_MEMOPT) $(ISP_PRINT_LEVEL) $(BR2_ISP_PARAMS) > $(TARGET_DIR)/etc/modules.d/20-isp; \
		fi \
	fi

	if [ "$(BR2_INGENIC_SDK_AVPU)" = "y" ]; then \
		echo "avpu $(AVPU_CLK_SRC) $(AVPU_CLK)" > $(TARGET_DIR)/etc/modules.d/10-avpu; \
	fi

	if [ "$(BR2_INGENIC_SDK_PWM)" = "y" ]; then \
		echo "pwm_core tcu_channels=0,1,3" >> $(TARGET_DIR)/etc/modules.d/15-pwm; \
		echo "pwm_hal" >> $(TARGET_DIR)/etc/modules.d/15-pwm; \
	fi

	if [ "$(SOC_FAMILY)" = "t40" ] || [ "$(SOC_FAMILY)" = "t41" ]; then \
		echo "mpsys-driver" >> $(TARGET_DIR)/etc/modules.d/06-mpsys; \
	fi

	if [ "$(BR2_THINGINO_NNA)" = "y" ] || [ "$(SOC_FAMILY)" = "t40" ] || [ "$(SOC_FAMILY)" = "t41" ]; then \
		echo "soc-nna" >> $(TARGET_DIR)/etc/modules.d/07-nna; \
	fi

	if [ "$(BR2_INGENIC_SDK_JZ_AES)" = "y" ]; then \
		echo "jz-aes" >> $(TARGET_DIR)/etc/modules.d/05-jz-aes; \
	fi

	if [ -n "$(SENSOR_1_MODEL)" ] && [ "$(SENSOR_1_MODEL)" != "none" ]; then \
		if [ -n "$(SENSOR_2_MODEL)" ] && [ "$(SENSOR_2_MODEL)" != "none" ]; then \
			echo "sensor_$(SENSOR_1_MODEL)_$(SOC_FAMILY) $(SENSOR_1_PARAMS)" > $(TARGET_DIR)/etc/modules.d/30-sensor_1; \
		else \
			echo "sensor_$(SENSOR_1_MODEL)_$(SOC_FAMILY) $(SENSOR_1_PARAMS)" > $(TARGET_DIR)/etc/modules.d/30-sensor; \
		fi; \
	fi

	if [ -n "$(SENSOR_2_MODEL)" ] && [ "$(SENSOR_2_MODEL)" != "none" ]; then \
		echo "sensor_$(SENSOR_2_MODEL)_$(SOC_FAMILY) $(SENSOR_2_PARAMS)" > $(TARGET_DIR)/etc/modules.d/30-sensor_2; \
	fi
endef

# The speaker-amp enable line comes from gpio.speaker in the board's
# thingino.json, in the same short notation as the rest of the gpio section:
# a bare int is an active-high pin, {"pin": N, "active_low": true} an
# active-low one. No key means the board has no amp gpio, which the codec
# module reads as spk_gpio=-1 (it gates every drive on spk_gpio > 0, so the
# level is moot). The same key is what package/thingino-uboot/
# inject-uboot-audio-dt.sh puts in the U-Boot device tree as
# ingenic,spk-gpio.
define INSTALL_AUDIO_SUPPORT
	spk_gpio=-1; \
	spk_level=1; \
	if [ -r $(INGENIC_SDK_CAMERA_JSON) ]; then \
		if [ ! -x $(INGENIC_SDK_JCT) ]; then \
			echo "ERROR: host jct tool missing: $(INGENIC_SDK_JCT)"; exit 1; \
		fi; \
		spk=$$($(INGENIC_SDK_JCT) $(INGENIC_SDK_CAMERA_JSON) get gpio.speaker.pin 2>/dev/null); \
		if [ -z "$$spk" ]; then \
			spk=$$($(INGENIC_SDK_JCT) $(INGENIC_SDK_CAMERA_JSON) get gpio.speaker 2>/dev/null); \
		fi; \
		case "$$spk" in \
			"" | *[!0-9]*) ;; \
			*) \
				spk_gpio=$$spk; \
				spk_al=$$($(INGENIC_SDK_JCT) $(INGENIC_SDK_CAMERA_JSON) get gpio.speaker.active_low 2>/dev/null); \
				if [ "$$spk_al" = "true" ]; then \
					spk_level=0; \
				fi; \
				;; \
		esac; \
	fi; \
	echo "audio spk_gpio=$$spk_gpio spk_level=$$spk_level $(BR2_THINGINO_AUDIO_PARAMS)" > $(TARGET_DIR)/etc/modules.d/40-audio

	[ -f $(@D)/config/webrtc_profile.ini ] && $(INSTALL) -D -m 0644 $(@D)/config/webrtc_profile.ini $(TARGET_DIR)/etc/

	$(INSTALL) -D -m 0755 $(INGENIC_SDK_PKGDIR)/files/speaker-ctrl $(TARGET_DIR)/usr/sbin/speaker-ctrl
endef

define INGENIC_SDK_INSTALL_TARGET_CMDS
	krel="$$( $(MAKE) -s -C $(LINUX_DIR) kernelrelease 2>/dev/null )"; \
	if [ -z "$$krel" ]; then krel="$(LINUX_VERSION_PROBED)"; fi; \
	for root in "$(TARGET_DIR)" "$(BASE_TARGET_DIR)"; do \
		[ -n "$$root" ] || continue; \
		[ -d "$$root" ] || continue; \
		libdir="$$root/lib"; \
		if [ "$(BR2_ROOTFS_MERGED_USR)" = "y" ]; then libdir="$$root/usr/lib"; fi; \
		find "$$libdir/modules" -mindepth 1 -maxdepth 1 -type d ! -name "$$krel" -exec rm -rf {} + 2>/dev/null || true; \
		$(INSTALL) -m 0755 -d "$$libdir/modules/$$krel"; \
		touch "$$libdir/modules/$$krel/modules.builtin.modinfo"; \
	done

	if [ -n "$(SENSOR_1_MODEL)" ]; then \
		$(call INSTALL_SENSOR_BIN,$(SENSOR_1_MODEL),$(SENSOR_1_BIN_NAME),$(SENSOR_1_CONFIG_NAME),$(SENSOR_1_IQ_OVERRIDE)); \
		$(call INSTALL_SENSOR_BIN,$(SENSOR_2_MODEL),$(SENSOR_2_BIN_NAME),$(SENSOR_2_CONFIG_NAME),$(SENSOR_2_IQ_OVERRIDE)); \
	fi

	$(GENERATE_MODULE_LOADER)
	$(GENERATE_GPIO_USERKEYS_CONFIG)
	[ "$(BR2_THINGINO_AUDIO)" = "y" ] && $(INSTALL_AUDIO_SUPPORT)
endef

$(eval $(kernel-module))
$(eval $(generic-package))
