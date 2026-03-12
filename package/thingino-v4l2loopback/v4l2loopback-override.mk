################################################################################
#
# v4l2loopback overrides for Thingino
#
################################################################################

ifeq ($(BR2_PACKAGE_THINGINO_V4L2LOOPBACK),y)

# v4l2loopback >= 0.13.x requires newer kernel APIs; pin to the last series
# known to work with Ingenic's kernel 3.10 branch.
override V4L2LOOPBACK_VERSION = 0.12.5
override V4L2LOOPBACK_SITE = $(call github,umlaeute,v4l2loopback,v$(V4L2LOOPBACK_VERSION))

# Append Ingenic-specific kernel config options needed by the ISP pipeline.
override define V4L2LOOPBACK_LINUX_CONFIG_FIXUPS
	$(call KCONFIG_ENABLE_OPT,CONFIG_DMA_SHARED_BUFFER)
	$(call KCONFIG_ENABLE_OPT,CONFIG_I2C)
	$(call KCONFIG_ENABLE_OPT,CONFIG_MEDIA_CAMERA_SUPPORT)
	$(call KCONFIG_ENABLE_OPT,CONFIG_MEDIA_CONTROLLER)
	$(call KCONFIG_ENABLE_OPT,CONFIG_MEDIA_SUPPORT)
	$(call KCONFIG_ENABLE_OPT,CONFIG_SOC_MCLK)
	$(call KCONFIG_ENABLE_OPT,CONFIG_V4L_PLATFORM_DRIVERS)
	$(call KCONFIG_ENABLE_OPT,CONFIG_VIDEO_ADV_DEBUG)
	$(call KCONFIG_ENABLE_OPT,CONFIG_VIDEO_DEV)
	$(call KCONFIG_ENABLE_OPT,CONFIG_VIDEO_TX_ISP)
	$(call KCONFIG_ENABLE_OPT,CONFIG_VIDEO_V4L2)
	$(call KCONFIG_ENABLE_OPT,CONFIG_VIDEO_V4L2_INT_DEVICE)
	$(call KCONFIG_ENABLE_OPT,CONFIG_VIDEO_V4L2_SUBDEV_API)
	$(call KCONFIG_ENABLE_OPT,CONFIG_VIDEOBUF2_CORE)
	$(call KCONFIG_ENABLE_OPT,CONFIG_VIDEOBUF2_MEMOPS)
endef

endif
