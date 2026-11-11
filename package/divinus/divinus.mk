DIVINUS_VERSION = f2fae7e0ce685116e6ec8e237db368472212317f
DIVINUS_SITE = https://github.com/openipc/divinus
DIVINUS_SITE_METHOD = git
DIVINUS_SITE_BRANCH = master
DIVINUS_LICENSE = MIT
DIVINUS_LICENSE_FILES = LICENSE

# Buildroot exports the git tree without .git, so the source Makefile's
# git describe fallback prints errors and embeds an empty revision.
DIVINUS_GIT_REV = $(shell echo $(DIVINUS_VERSION) | cut -c1-7)

define DIVINUS_BUILD_CMDS
	$(TARGET_MAKE_ENV) $(MAKE) -C $(@D)/src \
		CC="$(TARGET_CC)" \
		GIT_REV="$(DIVINUS_GIT_REV)" \
		OPT="$(TARGET_CFLAGS) -Os"
endef

define DIVINUS_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/divinus $(TARGET_DIR)/usr/bin/divinus
	$(INSTALL) -D -m 0644 $(DIVINUS_PKGDIR)/files/divinus.yaml \
		$(TARGET_DIR)/etc/divinus.yaml
endef

define DIVINUS_INSTALL_INIT_SYSV
	$(INSTALL) -D -m 0755 $(DIVINUS_PKGDIR)/files/S95divinus \
		$(TARGET_DIR)/etc/init.d/S95divinus
endef

$(eval $(generic-package))
