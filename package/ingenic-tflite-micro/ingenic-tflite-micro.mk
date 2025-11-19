################################################################################
#
# ingenic-tflite-micro
#
################################################################################

INGENIC_TFLITE_MICRO_VERSION = 0.0.2
INGENIC_TFLITE_MICRO_SITE = https://github.com/yinzara/ingenic-tflite-micro/releases/download/v$(INGENIC_TFLITE_MICRO_VERSION)
INGENIC_TFLITE_MICRO_LICENSE = Apache-2.0
INGENIC_TFLITE_MICRO_LICENSE_FILES = LICENSE
INGENIC_TFLITE_MICRO_INSTALL_STAGING = YES

# Install headers and library to staging for compile-time use
define INGENIC_TFLITE_MICRO_INSTALL_STAGING_CMDS
	mkdir -p $(STAGING_DIR)/usr/include
	cp -a $(@D)/include/tensorflow $(STAGING_DIR)/usr/include/
	cp -a $(@D)/include/third_party $(STAGING_DIR)/usr/include/
	cp -a $(@D)/include/signal $(STAGING_DIR)/usr/include/
	# Copy third_party contents to include root for direct access
	# gemmlowp -> fixedpoint/
	cp -a $(@D)/include/third_party/gemmlowp/* $(STAGING_DIR)/usr/include/
	# flatbuffers/include -> flatbuffers/
	cp -a $(@D)/include/third_party/flatbuffers/include/* $(STAGING_DIR)/usr/include/
	# ruy -> ruy/
	cp -a $(@D)/include/third_party/ruy/* $(STAGING_DIR)/usr/include/
	$(INSTALL) -D -m 0644 $(@D)/lib/libtflite-micro.a \
		$(STAGING_DIR)/usr/lib/libtflite-micro.a
endef

$(eval $(generic-package))
