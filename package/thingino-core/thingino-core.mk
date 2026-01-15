THINGINO_CORE_SITE_METHOD = local
THINGINO_CORE_SITE = $(BR2_EXTERNAL)/package/thingino-core

THINGINO_CORE_DEPENDENCIES = host-thingino-jct

THINGINO_CORE_OUTPUT_FILE=$(TARGET_DIR)/etc/thingino.json

define THINGINO_CORE_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0644 $(BR2_EXTERNAL)/configs/common.thingino.json \
		$(THINGINO_CORE_OUTPUT_FILE)

	CAMERA_CONFIG=$(BR2_EXTERNAL)/$(CAMERA_SUBDIR)/$(CAMERA)/thingino-camera.json; \
	[ -f "$$CAMERA_CONFIG" ] && \
		$(HOST_DIR)/bin/jct "$(THINGINO_CORE_OUTPUT_FILE)" import "$$CAMERA_CONFIG" || true

	USER_CONFIG=$(BR2_EXTERNAL)/configs/local.thingino.json; \
	[ -f "$$USER_CONFIG" ] && \
		$(HOST_DIR)/bin/jct "$(THINGINO_CORE_OUTPUT_FILE)" import "$$USER_CONFIG" || true

	printf "thingino-core: generated %s\n" $(THINGINO_CORE_OUTPUT_FILE) 1>&2
endef

$(eval $(generic-package))
