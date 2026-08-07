################################################################################
#
# sigmastar-sdk
#
# The kernel side of the SigmaStar vendor stack: prebuilt MI modules, sensor
# drivers built from source, and the tuning and firmware blobs the ISP and
# encoder read at runtime. Userspace lives in sigmastar-lib.
#
# The split follows thingino's Ingenic convention -- ingenic-lib is prebuilt
# userspace, ingenic-sdk is kernel-side and mixes prebuilt firmware archives
# with source compiled at build time. This does the same.
#
# One package per repository, deliberately: two packages pinning one repo means
# two clones and two hashes that can drift apart.
#
################################################################################

SIGMASTAR_SDK_SITE_METHOD = git
SIGMASTAR_SDK_SITE = https://github.com/johnchia/sigmastar-sdk
SIGMASTAR_SDK_SITE_BRANCH = main
SIGMASTAR_SDK_VERSION = cca10f4dba1ee1f3b856554494185d0e8ad7e2c8
SIGMASTAR_SDK_LICENSE = PROPRIETARY (mi modules), GPL-2.0 (sensor drivers)
SIGMASTAR_SDK_REDISTRIBUTE = NO

SIGMASTAR_SDK_DEPENDENCIES = linux

# Two kernel releases that must agree, from two different places.
#
# KREL is where the modules go on the target, and has to match what uname
# reports. LINUX_VERSION_PROBED gives that -- but it expands to a *backquoted
# shell command*, not a $(shell), so it only works inside a recipe. It must not
# reach anything make consumes directly: in MODULE_SUBDIRS the backticks never
# run and the embedded $(MAKE) leaks through as a path.
#
# VENDOR_KREL is where the payload sits inside the repo. That is a property of
# the fetched tree, so it is a literal.
#
# They are required to be equal: the vendor modules are prebuilt and insmod
# checks vermagic, which is why core-sigmastar.fragment pins the kernel. A
# mismatch fails loudly here, at a path that does not exist, rather than on the
# board.
#
# KERNEL_VERSION is deliberately NOT used for either. thingino.mk sets it to
# "4.9" for this vendor, which only names an output directory.
SIGMASTAR_SDK_KREL = $(LINUX_VERSION_PROBED)
SIGMASTAR_SDK_VENDOR_KREL = 4.9.84

# Prebuilt vendor modules, keyed by the build they came from and not merely by
# kernel release. Across a single vendor release the <libc>/<gcc> trees are not
# one source built several ways: mi_sys.ko differs by 27-29 imported kernel
# symbols between them, differs in `depends=`, and the trees ship different
# module sets. vermagic is byte-identical across all of them and
# CONFIG_MODVERSIONS is off, so insmod accepts a foreign module and it fails
# later at symbol resolution, or misbehaves. Nothing at load time catches it,
# which is why the flavour is spelled out here. See the repo's PROVENANCE.
SIGMASTAR_SDK_FLAVOUR = 0607-glibc-9.1.0
SIGMASTAR_SDK_KMOD = $(@D)/$(SIGMASTAR_SDK_VENDOR_KREL)/kmod-$(SIGMASTAR_SDK_FLAVOUR)

# Sensor drivers, compiled here, so no vermagic problem. No flavour key:
# drv_sensor.h is byte-identical between vendor releases nine months apart, and
# the built driver's only coupling to the vendor bundle is four CamOs* symbols
# from mhal.ko.
#
# Every driver the family has is built and installed. Selecting one is a runtime
# decision made by load_sigmastar from the U-Boot `sensor` variable; narrowing
# the build to the sensor on the development board is exactly what this must not
# do. INSTALL_MOD_DIR puts them in /lib/modules/<release>/sigmastar, alongside
# the prebuilt vendor modules and where load_sigmastar looks.
SIGMASTAR_SDK_MODULE_SUBDIRS = $(SIGMASTAR_SDK_VENDOR_KREL)/sensor-src/$(SOC_FAMILY)
SIGMASTAR_SDK_MODULE_MAKE_OPTS = \
	SENSOR_VERSION=$(SOC_FAMILY) \
	INSTALL_MOD_DIR=$(SOC_VENDOR) \
	KSRC=$(LINUX_DIR)

# Board-specific tuning, path relative to the BR2_EXTERNAL root as ingenic-sdk
# reads it. Left unset the stock blob is installed.
ifneq ($(call qstrip,$(BR2_SENSOR_1_IQ_FILE)),)
SIGMASTAR_SDK_IQ_OVERRIDE = \
	$(BR2_EXTERNAL_THINGINO_PATH)/$(call qstrip,$(BR2_SENSOR_1_IQ_FILE))
endif

define SIGMASTAR_SDK_INSTALL_TARGET_CMDS
	$(INSTALL) -m 755 -d $(TARGET_DIR)/lib/modules/$(SIGMASTAR_SDK_KREL)/sigmastar
	$(INSTALL) -m 644 -t $(TARGET_DIR)/lib/modules/$(SIGMASTAR_SDK_KREL)/sigmastar \
		$(SIGMASTAR_SDK_KMOD)/*

	# /etc/firmware is what MI_ISP_GetIspRoot reports on this board, so CUS3A
	# reads iqfile0.bin from here at AE init. chagall.bin is VENC firmware and
	# only shares the directory.
	$(INSTALL) -m 755 -d $(TARGET_DIR)/etc/firmware
	$(INSTALL) -m 644 -t $(TARGET_DIR)/etc/firmware $(@D)/iqfile/*
	$(INSTALL) -m 644 -t $(TARGET_DIR)/etc/firmware \
		$(@D)/venc_fw/$(SOC_FAMILY)/*

	# One sensor per target, in the shape ingenic-sdk installs: the blob under
	# /usr/share/sensor, an /etc/sensor symlink, and a model file.
	#
	# The plain <sensor>.bin name is required. raptor resolves the tuning by
	# the lowercased driver-module name, so ingenic-sdk's -$(SOC_FAMILY) suffix
	# would not be found and the board would come up on the generic tuning with
	# visibly wrong colour.
	#
	# All the family's bins stay in the repo -- another target selects its own.
	if [ -n "$(SENSOR_1_MODEL)" ]; then \
		$(INSTALL) -m 755 -d $(TARGET_DIR)/usr/share/sensor; \
		ln -sf /usr/share/sensor $(TARGET_DIR)/etc/sensor; \
		if [ -n "$(SIGMASTAR_SDK_IQ_OVERRIDE)" ] && \
		   [ -f "$(SIGMASTAR_SDK_IQ_OVERRIDE)" ]; then \
			$(INSTALL) -D -m 644 $(SIGMASTAR_SDK_IQ_OVERRIDE) \
				$(TARGET_DIR)/usr/share/sensor/$(SENSOR_1_MODEL).bin; \
		else \
			$(INSTALL) -D -m 644 \
				$(@D)/sensor-iq/$(SOC_FAMILY)/$(SENSOR_1_MODEL).bin \
				$(TARGET_DIR)/usr/share/sensor/$(SENSOR_1_MODEL).bin; \
		fi; \
		echo $(SENSOR_1_MODEL) > $(TARGET_DIR)/usr/share/sensor/model; \
	fi

	$(INSTALL) -m 755 -d $(TARGET_DIR)/usr/bin
	$(INSTALL) -m 755 -t $(TARGET_DIR)/usr/bin \
		$(SIGMASTAR_SDK_PKGDIR)/files/script/*

	$(INSTALL) -D -m 755 $(SIGMASTAR_SDK_PKGDIR)/files/S20sigmastar \
		$(TARGET_DIR)/etc/init.d/S20sigmastar
endef

$(eval $(kernel-module))
$(eval $(generic-package))
