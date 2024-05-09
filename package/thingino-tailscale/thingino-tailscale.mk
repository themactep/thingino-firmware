THINGINO_TAILSCALE_VERSION = $(shell curl -s -L https://api.github.com/repos/tailscale/tailscale/releases/latest | grep '"tag_name":' | head -n 1 | cut -d '"' -f 4 | sed 's/^v//')
THINGINO_TAILSCALE_SITE = https://pkgs.tailscale.com/stable
THINGINO_TAILSCALE_SOURCE = tailscale_$(THINGINO_TAILSCALE_VERSION)_mipsle.tgz

define DOWNLOAD_CMDS
	$(call DOWNLOAD,$(THINGINO_TAILSCALE_SITE)/$(THINGINO_TAILSCALE_SOURCE),$(THINGINO_TAILSCALE_DL_DIR)/$(THINGINO_TAILSCALE_SOURCE))
endef

define THINGINO_TAILSCALE_EXTRACT_CMDS
	tar -xzf $(THINGINO_TAILSCALE_DL_DIR)/$(THINGINO_TAILSCALE_SOURCE) -C $(@D)
endef

define THINGINO_TAILSCALE_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/tailscale_$(THINGINO_TAILSCALE_VERSION)_mipsle/tailscale $(TARGET_DIR)/usr/bin/tailscale
	$(INSTALL) -D -m 0755 $(@D)/tailscale_$(THINGINO_TAILSCALE_VERSION)_mipsle/tailscaled $(TARGET_DIR)/usr/bin/tailscaled
endef

$(eval $(generic-package))
