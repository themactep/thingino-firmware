################################################################################
#
# wireless_tools external tweaks (Thingino)
#
################################################################################

define WIRELESS_TOOLS_FIX_MERGED_USR
	if [ "$(BR2_ROOTFS_MERGED_USR)" = "y" ]; then \
		if [ -d "$(TARGET_DIR)/lib" ] && [ ! -L "$(TARGET_DIR)/lib" ]; then \
			mkdir -p "$(TARGET_DIR)/usr/lib"; \
			cp -a "$(TARGET_DIR)/lib/." "$(TARGET_DIR)/usr/lib/"; \
			rm -rf "$(TARGET_DIR)/lib"; \
			ln -s usr/lib "$(TARGET_DIR)/lib"; \
		fi; \
	fi
endef

WIRELESS_TOOLS_POST_INSTALL_TARGET_HOOKS += WIRELESS_TOOLS_FIX_MERGED_USR
