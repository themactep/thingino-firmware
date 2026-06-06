################################################################################
#
# scriba - flash chip programmer CLI for CH341A and EZP programmers (host tool)
#
################################################################################

SCRIBA_VERSION = c590b6a7c55043218c28d7f34d6c213d950d8b71
SCRIBA_SITE = $(call github,themactep,scriba,$(SCRIBA_VERSION))

SCRIBA_LICENSE = GPL-2.0
SCRIBA_LICENSE_FILES = LICENSE

HOST_SCRIBA_DEPENDENCIES = host-libusb

define HOST_SCRIBA_BUILD_CMDS
	$(HOSTCC) $(HOST_CFLAGS) \
		-std=gnu99 -Wall -O2 -D_FILE_OFFSET_BITS=64 \
		-DGIT_COMMIT_DATE=\"$(SCRIBA_VERSION)\" \
		-DGIT_COMMIT_HASH=\"$(SCRIBA_VERSION)\" \
		-DEEPROM_SUPPORT -I$(@D)/src \
		$(@D)/src/flashcmd_api.c \
		$(@D)/src/spi_controller.c \
		$(@D)/src/spi_nand_flash.c \
		$(@D)/src/spi_nand_flash_protocol.c \
		$(@D)/src/spi_nand_flash_tables.c \
		$(@D)/src/spi_nor_flash.c \
		$(@D)/src/ch341a_spi.c \
		$(@D)/src/ezp2019_spi.c \
		$(@D)/src/timer.c \
		$(@D)/src/main.c \
		$(@D)/src/ch341a_i2c.c \
		$(@D)/src/i2c_eeprom.c \
		$(@D)/src/spi_eeprom.c \
		$(@D)/src/bitbang_microwire.c \
		$(@D)/src/mw_eeprom.c \
		$(@D)/src/ch341a_gpio.c \
		$(HOST_LDFLAGS) -lusb-1.0 -lpthread \
		-o $(@D)/scriba
endef

define HOST_SCRIBA_INSTALL_CMDS
	$(INSTALL) -D -m 0755 $(@D)/scriba $(HOST_DIR)/bin/scriba
endef

$(eval $(host-generic-package))
