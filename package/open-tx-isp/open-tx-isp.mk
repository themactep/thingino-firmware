################################################################################
#
# open-tx-isp
#
################################################################################

OPEN_TX_ISP_SITE_METHOD = git
# Pinned to the thingino fork's T31 7.x line, not upstream: upstream
# (opensensor/open-tx-isp) stops short of the mainline port this tree needs on
# kernel 5.15/7.x - the vendor clock-name resolution and the 7.x kernel-API
# adaptation - and has no way to attach a drivers/media/i2c sensor to the
# vendor ABI. The branch is the full port, offered to Lu-Fi as a PR; it sits on
# that repo's next branch and carries the patches this package used to apply.
OPEN_TX_ISP_SITE = https://github.com/themactep/open-tx-isp
OPEN_TX_ISP_SITE_BRANCH = port/mainline-t31-7x
OPEN_TX_ISP_VERSION = 57d16f169e763422b66260c63c5efd65b08938e4
# external/ingenic-sdk carries the per-SoC sensor IQ tuning blobs
# (sensor-iq/<soc>/<model>.bin) installed by the open path; see the sensor IQ
# section below.
OPEN_TX_ISP_GIT_SUBMODULES = YES

# Upstream identifies the project as GPLv3 but does not currently ship a
# top-level license file for legal-info to collect.
OPEN_TX_ISP_LICENSE = GPL-3.0

# NOTE: no package patches. The 0001-0005 series in this directory was written
# against the old upstream pin; the pinned fork already carries that content
# (0001 t20 sinfo publish, 0002 t23 G_INPUT gate, 0004 t31 5.15 compat), a
# later implementation of it (0003 t23 frame wait, superseded there by
# "succeed only when a frame is ready"), and its own fix for 0005's problem
# (the kernel compat header supplies strlcpy()/strncpy() on 6.8+/7.2+). They
# are renamed to *.patch.disabled rather than deleted so they can be restored
# if the pin ever goes back to upstream.

# Modern kernels (5.15 vendor, 7.x mainline): the ingenic-sdk is disabled (its
# sensor/audio/AVPU modules are 4.4-only), so the open driver carries its own
# sensors from sensor-src/<soc>/. 3.10/4.4 keep using the SDK sensor module.
ifneq ($(filter 5.15.170 7.2.11,$(KERNEL_VERSION)),)
OPEN_TX_ISP_DEPENDENCIES = linux
OPEN_TX_ISP_MODULE_SUBDIRS = driver/$(SOC_FAMILY) sensor-src/$(SOC_FAMILY)
else
OPEN_TX_ISP_DEPENDENCIES = ingenic-sdk linux
# Build as out-of-tree kernel module
OPEN_TX_ISP_MODULE_SUBDIRS = driver/$(SOC_FAMILY)
endif

OPEN_TX_ISP_MODULE_MAKE_OPTS = \
	KDIR=$(LINUX_DIR) \
	INSTALL_MOD_PATH=$(TARGET_DIR) \
	INSTALL_MOD_DIR=ingenic \
	INSTALL_MOD_STRIP=--strip-unneeded \
	DIR=.

# The vendor 5.15 tree predates the mainline kernel APIs the T31 driver was
# recovered against (CONFIG_SET_FS was dropped, mediabus was renamed, ...);
# build it with the compatibility shim added by patch 0004.
ifeq ($(KERNEL_VERSION),5.15.170)
OPEN_TX_ISP_MODULE_MAKE_OPTS += TX_ISP_VENDOR_TREE=1
endif

# Development-only bring-up trace. Off by default; the trace adds ~220 KB
# and does not fit the standard rootfs, so release builds must leave it off.
ifeq ($(BR2_ISP_TRACE),y)
OPEN_TX_ISP_MODULE_MAKE_OPTS += TX_ISP_T31_TRACE=y
endif

# Add XBurst platform include paths for soc headers (the vendor trees carry
# arch/mips/xburst; the mainline 7.x tree does not).
ifneq ($(KERNEL_VERSION),7.2.11)
OPEN_TX_ISP_MODULE_MAKE_OPTS += \
	EXTRA_CFLAGS="-I$(LINUX_DIR)/arch/mips/xburst/soc-$(SOC_FAMILY)/include \
	-I$(LINUX_DIR)/arch/mips/xburst/core/include \
	-I$(LINUX_DIR)/arch/mips/xburst/common/include"
endif

# The T20 driver was written against the pre-refactor ingenic-sdk layout:
# it includes external/ingenic-sdk/{include,3.10.14/isp/t20,3.10.14/sensor-src/
# include}. Thingino's SDK override merged those trees under common/, so
# recreate the old paths as symlinks for the T20 build. Other families are
# self-contained and do not reference external/.
ifeq ($(SOC_FAMILY),t20)
OPEN_TX_ISP_SDK_DIR = $(firstword $(wildcard $(BUILD_DIR)/ingenic-sdk-*))
define OPEN_TX_ISP_T20_COMPAT_TREE
	mkdir -p $(@D)/external/ingenic-sdk/3.10.14/isp \
		$(@D)/external/ingenic-sdk/3.10.14/sensor-src
	ln -sfn $(OPEN_TX_ISP_SDK_DIR)/include \
		$(@D)/external/ingenic-sdk/include
	ln -sfn $(OPEN_TX_ISP_SDK_DIR)/common/isp/t20 \
		$(@D)/external/ingenic-sdk/3.10.14/isp/t20
	ln -sfn $(OPEN_TX_ISP_SDK_DIR)/common/sensor/include \
		$(@D)/external/ingenic-sdk/3.10.14/sensor-src/include
endef
OPEN_TX_ISP_PRE_BUILD_HOOKS += OPEN_TX_ISP_T20_COMPAT_TREE
endif

# The T31 driver exports functions annotated __init/__exit; the 5.15 kernel's
# modpost rejects that as a section mismatch. Downgrade it to a warning on the
# vendor tree so the module links. Kept as a separate variable so it lands on
# its own line inside the fixup define.
ifeq ($(KERNEL_VERSION),5.15.170)
OPEN_TX_ISP_MODPOST_FIXUP = $(call KCONFIG_ENABLE_OPT,CONFIG_SECTION_MISMATCH_WARN_ONLY)
endif

# The TX-ISP kernel modules build against the V4L2/media API, so enable that
# stack here instead of baking it into the shared generic kernel config.
#
# WARNING: only the SC2336 driver has been validated on hardware. Every other
# mainline sensor driver in this tree is a register-level port from the
# Ingenic vendor source and has not been tested on a camera.
#
# On the 7.2 mainline path the sensor drivers are built into the kernel (not
# modules): tx-isp's V4L2 bridge attaches to the subdev that probed from DT,
# and the vendor sensor module is neither built nor loaded. Enable only the
# driver this camera uses; CONFIG_VIDEO_<MODEL> matches the driver symbol.
ifeq ($(KERNEL_VERSION),7.2.11)
OPEN_TX_ISP_MAINLINE_SENSORS = sc2336 gc2053 gc4653 imx307 gc2083 gc4023 \
	imx327 jxf23 jxf37 jxq03 jxq03p os03b10 sc223a sc231hai sc2332 \
	sc2336p sc301iot sc3235 sc3335 sc3336 sc3338 sc401ai sc4236 \
	sc4336 sc4336p sc5235
ifneq ($(SENSOR_1_MODEL),)
OPEN_TX_ISP_SENSOR_1_CONFIG := CONFIG_VIDEO_$(shell echo $(SENSOR_1_MODEL) | tr a-z A-Z)
endif
ifneq ($(SENSOR_2_MODEL),)
OPEN_TX_ISP_SENSOR_2_CONFIG := CONFIG_VIDEO_$(shell echo $(SENSOR_2_MODEL) | tr a-z A-Z)
endif
endif

define OPEN_TX_ISP_LINUX_CONFIG_FIXUPS
	$(call KCONFIG_ENABLE_OPT,CONFIG_MEDIA_SUPPORT)
	$(call KCONFIG_ENABLE_OPT,CONFIG_MEDIA_SUPPORT_FILTER)
	$(call KCONFIG_ENABLE_OPT,CONFIG_MEDIA_CAMERA_SUPPORT)
	$(call KCONFIG_ENABLE_OPT,CONFIG_MEDIA_PLATFORM_SUPPORT)
	$(call KCONFIG_ENABLE_OPT,CONFIG_V4L_PLATFORM_DRIVERS)
	$(call KCONFIG_DISABLE_OPT,CONFIG_MEDIA_SUBDRV_AUTOSELECT)
	$(if $(OPEN_TX_ISP_SENSOR_1_CONFIG),$(call KCONFIG_ENABLE_OPT,$(OPEN_TX_ISP_SENSOR_1_CONFIG)))
	$(if $(OPEN_TX_ISP_SENSOR_2_CONFIG),$(call KCONFIG_ENABLE_OPT,$(OPEN_TX_ISP_SENSOR_2_CONFIG)))
	$(OPEN_TX_ISP_MODPOST_FIXUP)
endef

################################################################################
# Sensor IQ tuning blobs
################################################################################
# On the modern kernels the proprietary SDK is not built, so nothing populates
# /usr/share/sensor. The tuning blobs live in the ingenic-sdk tree that ships
# as open-tx-isp's external/ingenic-sdk submodule; install them with the same
# <model>[-<soc>].bin naming the proprietary path uses so the driver, the
# streamers and the webui find them. Missing blobs are not fatal: the driver
# falls back to its built-in tuning.
ifeq ($(BR2_THINGINO_DEV_CAMERA),y)
OPEN_TX_ISP_SENSOR_IQ_DIR = $(@D)/external/ingenic-sdk/sensor-iq/$(SOC_FAMILY)

# t10/t20/t30 predate the per-SoC IQ file name.
ifneq ($(filter $(SOC_FAMILY),t10 t20 t30),)
OPEN_TX_ISP_IQ_1_NAME = $(SENSOR_1_MODEL).bin
OPEN_TX_ISP_IQ_2_NAME = $(SENSOR_2_MODEL).bin
OPEN_TX_ISP_IQ_1_CUST = $(SENSOR_1_MODEL)-cust.bin
OPEN_TX_ISP_IQ_2_CUST = $(SENSOR_2_MODEL)-cust.bin
else
OPEN_TX_ISP_IQ_1_NAME = $(SENSOR_1_MODEL)-$(SOC_FAMILY).bin
OPEN_TX_ISP_IQ_2_NAME = $(SENSOR_2_MODEL)-$(SOC_FAMILY).bin
OPEN_TX_ISP_IQ_1_CUST = $(SENSOR_1_MODEL)-cust-$(SOC_FAMILY).bin
OPEN_TX_ISP_IQ_2_CUST = $(SENSOR_2_MODEL)-cust-$(SOC_FAMILY).bin
endif

# $(call OPEN_TX_ISP_INSTALL_IQ,model,installed-name,override,cust-name)
# override is a bare file name resolved under sensor-iq/<soc>/, or a path
# relative to BR2_EXTERNAL. A per-board <model>-cust.bin sibling is installed
# as cust-name (the name the driver probes for, e.g. sc2336-cust-t31.bin) when
# no explicit override is set, matching the proprietary path.
define OPEN_TX_ISP_INSTALL_IQ
	if [ -n "$(1)" ] && [ "$(1)" != "none" ]; then \
		iqdir='$(OPEN_TX_ISP_SENSOR_IQ_DIR)'; \
		iqfile='$(3)'; \
		[ -n "$$iqfile" ] || iqfile='$(1).bin'; \
		case "$$iqfile" in \
			*/*) iqfile="$(BR2_EXTERNAL_THINGINO_PATH)/$$iqfile" ;; \
			*)   iqfile="$$iqdir/$$iqfile" ;; \
		esac; \
		if [ -f "$$iqfile" ]; then \
			$(INSTALL) -D -m 0644 "$$iqfile" "$(TARGET_DIR)/usr/share/sensor/$(2)"; \
			if [ -z "$(3)" ] && [ -f "$$iqdir/$(1)-cust.bin" ]; then \
				$(INSTALL) -D -m 0644 "$$iqdir/$(1)-cust.bin" \
					"$(TARGET_DIR)/usr/share/sensor/$(4)"; \
			fi; \
		else \
			echo "open-tx-isp: sensor IQ '$$iqfile' for $(1) not found; using built-in tuning"; \
		fi; \
	fi
endef

define OPEN_TX_ISP_INSTALL_SENSOR_IQ
	$(INSTALL) -d $(TARGET_DIR)/usr/share/sensor
	if [ -n "$(SENSOR_1_MODEL)" ] && [ "$(SENSOR_1_MODEL)" != "none" ]; then \
		ln -sf /usr/share/sensor $(TARGET_DIR)/etc/sensor; \
		echo $(SENSOR_1_MODEL) > $(TARGET_DIR)/usr/share/sensor/model; \
	fi
	$(call OPEN_TX_ISP_INSTALL_IQ,$(SENSOR_1_MODEL),$(OPEN_TX_ISP_IQ_1_NAME),$(call qstrip,$(BR2_SENSOR_1_IQ_FILE)),$(OPEN_TX_ISP_IQ_1_CUST))
	$(call OPEN_TX_ISP_INSTALL_IQ,$(SENSOR_2_MODEL),$(OPEN_TX_ISP_IQ_2_NAME),$(call qstrip,$(BR2_SENSOR_2_IQ_FILE)),$(OPEN_TX_ISP_IQ_2_CUST))
endef
OPEN_TX_ISP_POST_INSTALL_TARGET_HOOKS += OPEN_TX_ISP_INSTALL_SENSOR_IQ
endif

################################################################################
# /etc/modules.d loaders for the modern (5.15/7.x) path
################################################################################
# On the modern kernels the proprietary ingenic-sdk is not built (its ISP and
# sensor modules are 4.4-only), so nothing writes /etc/modules.d/20-isp and
# 30-sensor and the ISP + sensor modules are never loaded at boot. The
# streamer's HAL init then loops on IMP_ISP_Open forever and RTSP never comes
# up. Install the same loaders the SDK path would have written.
ifneq ($(filter 5.15.170 7.2.11,$(KERNEL_VERSION)),)
ifeq ($(BR2_THINGINO_DEV_CAMERA),y)
define OPEN_TX_ISP_INSTALL_MODULES_D
	$(INSTALL) -d $(TARGET_DIR)/etc/modules.d
	echo "tx_isp_$(SOC_FAMILY) $(ISP_CLK) $(ISP_DAY_NIGHT_SWITCH_DROP_FRAME_NUM) $(ISP_CH0_PRE_DEQUEUE_TIME) $(ISP_CH0_PRE_DEQUEUE_INTERRUPT_PROCESS) $(ISP_CH0_PRE_DEQUEUE_VALID_LINES) $(ISP_CH1_DEQUEUE_DELAY_TIME) $(ISP_MEMOPT) $(ISP_PRINT_LEVEL) $(BR2_ISP_PARAMS)" \
		> $(TARGET_DIR)/etc/modules.d/20-isp
	if [ -n "$(SENSOR_1_MODEL)" ] && [ "$(SENSOR_1_MODEL)" != "none" ]; then \
		case " $(OPEN_TX_ISP_MAINLINE_SENSORS) " in \
			*" $(SENSOR_1_MODEL) "*) \
				rm -f $(TARGET_DIR)/etc/modules.d/30-sensor \
					$(TARGET_DIR)/lib/modules/$(LINUX_VERSION)/ingenic/sensor_$(SENSOR_1_MODEL)_$(SOC_FAMILY).ko ;; \
			*) echo "sensor_$(SENSOR_1_MODEL)_$(SOC_FAMILY) $(SENSOR_1_PARAMS)" \
				> $(TARGET_DIR)/etc/modules.d/30-sensor ;; \
		esac; \
	fi
endef
OPEN_TX_ISP_POST_INSTALL_TARGET_HOOKS += OPEN_TX_ISP_INSTALL_MODULES_D
endif
endif

$(eval $(kernel-module))

# The vendor sensor-src/$(SOC_FAMILY) Kbuild declares every sensor it carries
# as obj-m, so a plain "modules" build compiles them all. Trim it to the
# sensor(s) this camera loads (see /etc/modules.d/30-sensor) before the
# kernel-module build hook runs, so only those are built and installed.
OPEN_TX_ISP_SENSOR_MODELS = $(filter-out none,$(SENSOR_1_MODEL) $(SENSOR_2_MODEL))
# Sensors with an in-tree V4L2 driver, consumed through tx-isp's V4L2 bridge.
OPEN_TX_ISP_VENDOR_SENSORS = $(filter-out $(OPEN_TX_ISP_MAINLINE_SENSORS),$(OPEN_TX_ISP_SENSOR_MODELS))

define OPEN_TX_ISP_LIMIT_SENSORS
	if [ -f "$(@D)/sensor-src/$(SOC_FAMILY)/Kbuild" ]; then \
		$(SED) '/^obj-m += sensor_/d' "$(@D)/sensor-src/$(SOC_FAMILY)/Kbuild"; \
		for m in $(OPEN_TX_ISP_VENDOR_SENSORS); do \
			echo "obj-m += sensor_$${m}_$(SOC_FAMILY).o" \
				>> "$(@D)/sensor-src/$(SOC_FAMILY)/Kbuild"; \
		done; \
	fi
endef
OPEN_TX_ISP_PRE_BUILD_HOOKS += OPEN_TX_ISP_LIMIT_SENSORS

# Bring-up visibility: report which sensor path this build selected.
define OPEN_TX_ISP_REPORT_SENSOR
	@echo ">>> open-tx-isp: sensors $(or $(SENSOR_1_MODEL),none)$(if $(SENSOR_2_MODEL), + $(SENSOR_2_MODEL))"
	@echo ">>> open-tx-isp: mainline driver $(if $(OPEN_TX_ISP_SENSOR_1_CONFIG),$(OPEN_TX_ISP_SENSOR_1_CONFIG)=y,$(if $(OPEN_TX_ISP_SENSOR_2_CONFIG),$(OPEN_TX_ISP_SENSOR_2_CONFIG)=y,none))"
	@echo ">>> open-tx-isp: legacy modules $(if $(OPEN_TX_ISP_VENDOR_SENSORS),$(OPEN_TX_ISP_VENDOR_SENSORS),none)"
endef
OPEN_TX_ISP_PRE_BUILD_HOOKS += OPEN_TX_ISP_REPORT_SENSOR

$(eval $(generic-package))
