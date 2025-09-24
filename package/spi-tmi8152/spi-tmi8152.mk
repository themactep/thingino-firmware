SPI_TMI8152_SITE_METHOD = git
SPI_TMI8152_SITE = https://github.com/sstepansky/tmi8152-spi-dev
SPI_TMI8152_SITE_BRANCH = main
SPI_TMI8152_VERSION = c8713a50a76f0ac9f4b84aca7e985d7dab502c38
# $(shell git ls-remote $(SPI_TMI8152_SITE) $(SPI_TMI8152_SITE_BRANCH) | head -1 | cut -f1)

SPI_TMI8152_LICENSE = GPL-2.0
SPI_TMI8152_LICENSE_FILES = LICENSE

SPI_TMI8152_MODULE_MAKE_OPTS = \
	KSRC=$(LINUX_DIR)

define SPI_TMI8152_LINUX_CONFIG_FIXUPS
	$(call KCONFIG_ENABLE_OPT,CONFIG_SPI)
	$(call KCONFIG_ENABLE_OPT,CONFIG_JZ_SPI)
	$(call KCONFIG_ENABLE_OPT,CONFIG_JZ_SPI0)
endef

TARGET_MODULES_PATH = $(TARGET_DIR)/lib/modules/$(FULL_KERNEL_VERSION)$(call qstrip,$(LINUX_CONFIG_LOCALVERSION))
define SPI_TMI8152_INSTALL_TARGET_CMDS
	$(INSTALL) -m 0755 -d $(TARGET_MODULES_PATH)
	touch $(TARGET_MODULES_PATH)/modules.builtin.modinfo

	$(INSTALL) -D -m 0644 $(@D)/tmi8152_spi_dev.ko \
		$(TARGET_MODULES_PATH)/extra/tmi8152_spi_dev.ko

	$(INSTALL) -m 0755 -d $(TARGET_DIR)/etc
	echo tmi8152_spi_dev.ko >> $(TARGET_DIR)/etc/modules
endef

$(eval $(kernel-module))
$(eval $(generic-package))
