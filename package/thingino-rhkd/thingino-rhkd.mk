################################################################################
#
# thingino-rhkd: native HomeKit camera daemon
#
################################################################################

THINGINO_RHKD_SITE_METHOD = git
THINGINO_RHKD_SITE = https://github.com/Small6oy/thingino-homekit
# v0.7.2
THINGINO_RHKD_VERSION = 1f41db756dc9a4fbd8fedbe3e7a7929c62c06b96
THINGINO_RHKD_LICENSE = GPL-3.0-or-later (rhkd, raptor-ipc), Apache-2.0 (HomeKitADK, mbedTLS, parts of rhkd), BSD-3-Clause (Opus), LGPL-2.1+ (faac)
# The extra downloads are unpacked into src/ at extract time (below), so their licenses reach legal-info.
THINGINO_RHKD_LICENSE_FILES = LICENSE src/HomeKitADK/LICENSE.md src/mbedtls/LICENSE src/raptor-ipc/LICENSE \
	src/opus/COPYING src/faac/COPYING

# Third-party sources, at the commits (mbedTLS: the release tag) that rhkd's deps.sh pins. They are
# hash-checked (thingino-rhkd.hash); the main git tarball is exempt, as for compy.
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

BR_NO_CHECK_HASH_FOR += $(THINGINO_RHKD_SOURCE)

# Unpack each extra download into src/<name> unless that tree is already there (an override source dir
# may bring its own), then apply each of rhkd's HomeKitADK patches that isn't applied yet: checked per
# patch, so an override with an unpatched ADK still gets them and a patched one isn't patched twice.
# Runs right after extract (or rsync, for overrides), so legal-info finds the license files.
define THINGINO_RHKD_UNPACK_DEP
	if [ ! -e $(@D)/src/$(1)/$(3) ]; then \
		mkdir -p $(@D)/src/$(1) && \
		tar -xzf $(THINGINO_RHKD_DL_DIR)/$(2) --strip-components=1 -C $(@D)/src/$(1) || exit 1; \
	fi
endef

define THINGINO_RHKD_FETCH_DEPS
	$(call THINGINO_RHKD_UNPACK_DEP,HomeKitADK,$(THINGINO_RHKD_ADK_COMMIT).tar.gz,LICENSE.md)
	$(call THINGINO_RHKD_UNPACK_DEP,mbedtls,v$(THINGINO_RHKD_MBEDTLS_VERSION).tar.gz,LICENSE)
	$(call THINGINO_RHKD_UNPACK_DEP,raptor-ipc,$(THINGINO_RHKD_RIPC_COMMIT).tar.gz,LICENSE)
	$(call THINGINO_RHKD_UNPACK_DEP,opus,$(THINGINO_RHKD_OPUS_COMMIT).tar.gz,COPYING)
	$(call THINGINO_RHKD_UNPACK_DEP,faac,$(THINGINO_RHKD_FAAC_COMMIT).tar.gz,COPYING)
	for p in $(@D)/patches/HomeKitADK/*.patch; do \
		if patch -d $(@D)/src/HomeKitADK -p1 -R -s -f --dry-run <$$p >/dev/null 2>&1; then continue; fi; \
		patch -d $(@D)/src/HomeKitADK -p1 -s <$$p || exit 1; \
	done
endef
THINGINO_RHKD_POST_EXTRACT_HOOKS += THINGINO_RHKD_FETCH_DEPS
THINGINO_RHKD_POST_RSYNC_HOOKS += THINGINO_RHKD_FETCH_DEPS

THINGINO_RHKD_MAKE_OPTS = \
	CROSS="$(TARGET_CROSS)" \
	ARCHFLAGS="" \
	EXTRA_CFLAGS="$(TARGET_CFLAGS)" \
	EXTRA_LDFLAGS="$(TARGET_LDFLAGS)" \
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
# Each path is checked on its own, so a list that already has one of them still gets the other.
define THINGINO_RHKD_CFG_BACKUP
	f=$(TARGET_DIR)/etc/cfg-backup.list; \
	if [ -f $$f ]; then \
		grep -q '^# HomeKit (rhkd)' $$f || printf '\n# HomeKit (rhkd): pairing store, setup code, settings\n' >>$$f; \
		grep -qx '/etc/homekit' $$f || echo '/etc/homekit' >>$$f; \
		grep -qx '/etc/default/rhkd' $$f || echo '/etc/default/rhkd' >>$$f; \
	fi
endef
ROOTFS_PRE_CMD_HOOKS += THINGINO_RHKD_CFG_BACKUP

$(eval $(generic-package))
