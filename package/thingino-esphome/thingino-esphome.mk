################################################################################
#
# thingino-esphome
#
################################################################################

THINGINO_ESPHOME_VERSION = v0.0.13
THINGINO_ESPHOME_SITE = https://github.com/yinzara/esphome-linux
THINGINO_ESPHOME_SITE_METHOD = git
THINGINO_ESPHOME_SITE_BRANCH = main
THINGINO_ESPHOME_LICENSE = MIT
THINGINO_ESPHOME_LICENSE_FILES = LICENSE

# Base dependencies
THINGINO_ESPHOME_DEPENDENCIES = host-meson host-pkgconf thingino-libcurl ingenic-audiodaemon

# Add Bluetooth dependencies if Bluetooth is enabled
ifeq ($(BR2_PACKAGE_THINGINO_BLUETOOTH),y)
THINGINO_ESPHOME_DEPENDENCIES += thingino-libble
endif

# Add TFLite Micro and microspeech features dependencies if wake word is enabled
ifeq ($(BR2_PACKAGE_THINGINO_ESPHOME_WAKE_WORD),y)
THINGINO_ESPHOME_DEPENDENCIES += ingenic-tflite-micro esp-microspeech-features
endif

# Copy local plugins into the build directory before configuring
# Also merge any plugin meson_options.txt into the main meson_options.txt
define THINGINO_ESPHOME_COPY_PLUGINS
	if [ -d $(THINGINO_ESPHOME_PKGDIR)/plugins ]; then \
		mkdir -p $(@D)/plugins; \
		cp -r $(THINGINO_ESPHOME_PKGDIR)/plugins/* $(@D)/plugins/; \
		echo "Copied Thingino-specific plugins to build directory"; \
		for opts in $(@D)/plugins/*/meson_options.txt; do \
			if [ -f "$$opts" ]; then \
				echo "" >> $(@D)/meson_options.txt; \
				echo "# Options from $$(dirname $$opts | xargs basename)" >> $(@D)/meson_options.txt; \
				cat "$$opts" >> $(@D)/meson_options.txt; \
				echo "Merged plugin options: $$opts"; \
			fi; \
		done; \
	fi
endef
THINGINO_ESPHOME_PRE_CONFIGURE_HOOKS += THINGINO_ESPHOME_COPY_PLUGINS

# Meson build options
THINGINO_ESPHOME_CONF_OPTS =

# Enable Bluetooth Proxy only if Thingino Bluetooth is enabled
ifeq ($(BR2_PACKAGE_THINGINO_BLUETOOTH),y)
THINGINO_ESPHOME_CONF_OPTS += -Denable_bluetooth_proxy=true
else
THINGINO_ESPHOME_CONF_OPTS += -Denable_bluetooth_proxy=false
endif

# Always enable plugins
THINGINO_ESPHOME_CONF_OPTS += -Denable_plugins=true

# Enable wake word detection if TFLite Micro is available
ifeq ($(BR2_PACKAGE_THINGINO_ESPHOME_WAKE_WORD),y)
THINGINO_ESPHOME_CONF_OPTS += -Denable_wake_word=true
else
THINGINO_ESPHOME_CONF_OPTS += -Denable_wake_word=false
endif

# Install init script
define THINGINO_ESPHOME_INSTALL_INIT_SYSV
	$(INSTALL) -D -m 0755 $(THINGINO_ESPHOME_PKGDIR)/files/S60esphome-service \
		$(TARGET_DIR)/etc/init.d/S60esphome-service
endef

# Install wake word model - prefer overlay, fall back to package files
define THINGINO_ESPHOME_INSTALL_WAKE_WORD_MODEL
	if [ -f $(TOPDIR)/../overlay/upper/etc/wake_word_model.tflite ]; then \
		$(INSTALL) -D -m 0644 $(TOPDIR)/../overlay/upper/etc/wake_word_model.tflite \
			$(TARGET_DIR)/etc/wake_word_model.tflite; \
		echo "Installed wake word model from overlay to /etc/wake_word_model.tflite"; \
	elif [ -f $(THINGINO_ESPHOME_PKGDIR)/files/wake_word_model.tflite ]; then \
		$(INSTALL) -D -m 0644 $(THINGINO_ESPHOME_PKGDIR)/files/wake_word_model.tflite \
			$(TARGET_DIR)/etc/wake_word_model.tflite; \
		echo "Installed default wake word model to /etc/wake_word_model.tflite"; \
	fi
endef
ifeq ($(BR2_PACKAGE_THINGINO_ESPHOME_WAKE_WORD),y)
THINGINO_ESPHOME_POST_INSTALL_TARGET_HOOKS += THINGINO_ESPHOME_INSTALL_WAKE_WORD_MODEL
endif

$(eval $(meson-package))
