################################################################################
#
# esp-microspeech-features
#
################################################################################

ESP_MICROSPEECH_FEATURES_VERSION = 1.1.0
ESP_MICROSPEECH_FEATURES_SITE = $(call github,kahrendt,ESPMicroSpeechFeatures,v$(ESP_MICROSPEECH_FEATURES_VERSION))
ESP_MICROSPEECH_FEATURES_LICENSE = Apache-2.0
ESP_MICROSPEECH_FEATURES_LICENSE_FILES = LICENSE
ESP_MICROSPEECH_FEATURES_INSTALL_STAGING = YES

# Source files from the repository
ESP_MICROSPEECH_FEATURES_SRCS = \
	fft.c \
	fft_util.c \
	filterbank.c \
	filterbank_util.c \
	frontend.c \
	frontend_util.c \
	kiss_fft.c \
	kiss_fftr.c \
	log_lut.c \
	log_scale.c \
	log_scale_util.c \
	noise_reduction.c \
	noise_reduction_util.c \
	pcan_gain_control.c \
	pcan_gain_control_util.c \
	window.c \
	window_util.c

define ESP_MICROSPEECH_FEATURES_BUILD_CMDS
	cd $(@D) && $(TARGET_MAKE_ENV) $(TARGET_CC) $(TARGET_CFLAGS) -include stdint.h -I$(@D)/src -I$(@D)/include \
		-c $(addprefix $(@D)/src/,$(ESP_MICROSPEECH_FEATURES_SRCS)) && \
	$(TARGET_AR) rcs $(@D)/libesp-microspeech-features.a $(@D)/*.o
endef

define ESP_MICROSPEECH_FEATURES_INSTALL_STAGING_CMDS
	mkdir -p $(STAGING_DIR)/usr/include/microspeech/include
	mkdir -p $(STAGING_DIR)/usr/include/microspeech/src
	cp $(@D)/include/*.h $(STAGING_DIR)/usr/include/microspeech/include/
	cp $(@D)/src/*.h $(STAGING_DIR)/usr/include/microspeech/src/
	$(INSTALL) -D -m 0644 $(@D)/libesp-microspeech-features.a \
		$(STAGING_DIR)/usr/lib/libesp-microspeech-features.a
endef

$(eval $(generic-package))
