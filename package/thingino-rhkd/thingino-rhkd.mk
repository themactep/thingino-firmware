################################################################################
#
# thingino-rhkd: native HomeKit camera daemon
#
################################################################################

THINGINO_RHKD_SITE_METHOD = git
THINGINO_RHKD_SITE = https://github.com/Small6oy/thingino-homekit
# v0.7.0
THINGINO_RHKD_VERSION = 044a14f9a658c065f304cdd2b6085a9c3ff3714c
THINGINO_RHKD_LICENSE = GPL-3.0-or-later, Apache-2.0 (HomeKitADK, mbedTLS, parts of rhkd), BSD-3-Clause (Opus), LGPL-2.1+ (faac)
THINGINO_RHKD_LICENSE_FILES = LICENSE

# Third-party sources, at the commits rhkd's deps.sh pins.
THINGINO_RHKD_ADK_COMMIT = fb201f98f5fdc7fef6a455054f08b59cca5d1ec8
THINGINO_RHKD_MBEDTLS_VERSION = 2.28.10
THINGINO_RHKD_RIPC_COMMIT = 00810bb7b91c3e21210b5a76d43748a23758f36a
# HomeKit Secure Video audio: Opus (raptor's ring) -> PCM -> AAC-LC.
THINGINO_RHKD_OPUS_COMMIT = ddbe48383984d56acd9e1ab6a090c54ca6b735a6
THINGINO_RHKD_FAAC_COMMIT = 78d8e0141600ac006a94ac6fd5601f599fa5b65b
THINGINO_RHKD_EXTRA_DOWNLOADS = \
	https://github.com/apple/HomeKitADK/archive/$(THINGINO_RHKD_ADK_COMMIT).tar.gz \
	https://github.com/Mbed-TLS/mbedtls/archive/refs/tags/v$(THINGINO_RHKD_MBEDTLS_VERSION).tar.gz \
	https://github.com/gtxaspec/raptor-ipc/archive/$(THINGINO_RHKD_RIPC_COMMIT).tar.gz \
	https://github.com/xiph/opus/archive/$(THINGINO_RHKD_OPUS_COMMIT).tar.gz \
	https://github.com/knik0/faac/archive/$(THINGINO_RHKD_FAAC_COMMIT).tar.gz

# Unpack the extra downloads into src/ (unless an override source dir already has them), then apply
# rhkd's HomeKitADK patches.
define THINGINO_RHKD_FETCH_DEPS
	if [ ! -d $(@D)/src/HomeKitADK/HAP ]; then \
		mkdir -p $(@D)/src/HomeKitADK $(@D)/src/mbedtls $(@D)/src/raptor-ipc $(@D)/src/opus $(@D)/src/faac && \
		tar -xzf $(THINGINO_RHKD_DL_DIR)/$(THINGINO_RHKD_ADK_COMMIT).tar.gz --strip-components=1 -C $(@D)/src/HomeKitADK && \
		tar -xzf $(THINGINO_RHKD_DL_DIR)/v$(THINGINO_RHKD_MBEDTLS_VERSION).tar.gz --strip-components=1 -C $(@D)/src/mbedtls && \
		tar -xzf $(THINGINO_RHKD_DL_DIR)/$(THINGINO_RHKD_RIPC_COMMIT).tar.gz --strip-components=1 -C $(@D)/src/raptor-ipc && \
		tar -xzf $(THINGINO_RHKD_DL_DIR)/$(THINGINO_RHKD_OPUS_COMMIT).tar.gz --strip-components=1 -C $(@D)/src/opus && \
		tar -xzf $(THINGINO_RHKD_DL_DIR)/$(THINGINO_RHKD_FAAC_COMMIT).tar.gz --strip-components=1 -C $(@D)/src/faac && \
		for p in $(@D)/patches/HomeKitADK/*.patch; do patch -d $(@D)/src/HomeKitADK -p1 < $$p || exit 1; done; \
	fi
endef
THINGINO_RHKD_PRE_BUILD_HOOKS += THINGINO_RHKD_FETCH_DEPS

THINGINO_RHKD_MAKE_OPTS = \
	CROSS="$(TARGET_CROSS)" \
	ARCHFLAGS="" \
	EXTRA_CFLAGS="$(TARGET_CFLAGS)" \
	STATIC="" \
	LOG_LEVEL=3

define THINGINO_RHKD_BUILD_CMDS
	$(TARGET_MAKE_ENV) $(MAKE) -C $(@D)/build $(THINGINO_RHKD_MAKE_OPTS) out/rhkd out/hap-setupgen
endef

define THINGINO_RHKD_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/build/out/rhkd $(TARGET_DIR)/usr/bin/rhkd
	$(INSTALL) -D -m 0755 $(@D)/build/out/hap-setupgen $(TARGET_DIR)/usr/bin/hap-setupgen
	$(INSTALL) -D -m 0755 $(@D)/files/usr/sbin/rhkd-setup $(TARGET_DIR)/usr/sbin/rhkd-setup
	$(INSTALL) -D -m 0755 $(@D)/files/etc/init.d/S98rhkd $(TARGET_DIR)/etc/init.d/S98rhkd
	$(INSTALL) -D -m 0644 $(@D)/files/etc/default/rhkd $(TARGET_DIR)/etc/default/rhkd
	$(INSTALL) -D -m 0644 $(@D)/files/var/www/config-homekit.html $(TARGET_DIR)/var/www/config-homekit.html
	$(INSTALL) -D -m 0644 $(@D)/files/var/www/a/config-homekit.js $(TARGET_DIR)/var/www/a/config-homekit.js
	$(INSTALL) -D -m 0644 $(@D)/files/var/www/a/vendor/qrcode.js $(TARGET_DIR)/var/www/a/vendor/qrcode.js
	$(INSTALL) -D -m 0755 $(@D)/files/var/www/x/json-homekit.cgi $(TARGET_DIR)/var/www/x/json-homekit.cgi
	$(INSTALL) -D -m 0644 $(THINGINO_RHKD_PKGDIR)/files/homekit.webui.json \
		$(TARGET_DIR)/var/www/a/plugins/homekit.webui.json
endef

# Keep pairing across firmware upgrades: sysupgrade -B saves the paths in /etc/cfg-backup.list to the
# backup partition, and S37cfg-autorestore restores them on first boot.
# Must be a ROOTFS_PRE_CMD_HOOK, not a TARGET_FINALIZE_HOOK: cfg-backup.list comes from BR2_ROOTFS_OVERLAY,
# which target-finalize copies in after its hooks run (see package/thingino-sounds).
define THINGINO_RHKD_CFG_BACKUP
	if [ -f $(TARGET_DIR)/etc/cfg-backup.list ] && ! grep -q '^/etc/homekit$$' $(TARGET_DIR)/etc/cfg-backup.list; then \
		printf '\n# HomeKit (rhkd): pairing store, setup code, settings\n/etc/homekit\n/etc/default/rhkd\n' \
			>>$(TARGET_DIR)/etc/cfg-backup.list; \
	fi
endef
ROOTFS_PRE_CMD_HOOKS += THINGINO_RHKD_CFG_BACKUP

$(eval $(generic-package))
