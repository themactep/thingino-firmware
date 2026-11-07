THINGINO_CORE_SITE_METHOD = local
THINGINO_CORE_SITE = $(BR2_EXTERNAL_THINGINO_PATH)/package/thingino-core

THINGINO_CORE_DEPENDENCIES = host-thingino-jct

THINGINO_CORE_OUTPUT_FILE = $(TARGET_DIR)/etc/thingino.json
THINGINO_CORE_STAGING_DIR = $(TARGET_DIR)/usr/share/thingino-defaults

define THINGINO_CORE_INSTALL_TARGET_CMDS
	# Create the base thingino.json and staging directory
	$(INSTALL) -D -m 0644 $(BR2_EXTERNAL_THINGINO_PATH)/configs/common.thingino.json \
		$(THINGINO_CORE_OUTPUT_FILE)
	$(INSTALL) -d $(THINGINO_CORE_STAGING_DIR)

	# Stage camera-specific overrides for later merge
	CAMERA_CONFIG=$(BR2_EXTERNAL_THINGINO_PATH)/$(CAMERA_SUBDIR)/$(CAMERA)/thingino.json; \
	[ -f "$$CAMERA_CONFIG" ] && \
		$(INSTALL) -m 0644 "$$CAMERA_CONFIG" $(THINGINO_CORE_STAGING_DIR)/90-camera.json || true

	printf "thingino-core: staged %s\n" $(THINGINO_CORE_OUTPUT_FILE) 1>&2
endef

# Merge all staged JSON fragments and user configs during target-finalize.
# This runs after every package has installed its staging files, so there
# is no race on thingino.json.
define THINGINO_CORE_MERGE_THINGINO_JSON
	# Merge staging files in sorted (priority) order
	for FRAGMENT in $(THINGINO_CORE_STAGING_DIR)/*.json; do \
		[ -f "$$FRAGMENT" ] && \
			$(HOST_DIR)/bin/jct "$(THINGINO_CORE_OUTPUT_FILE)" import "$$FRAGMENT" || true; \
	done

	# Apply user overrides last (non-empty only, to avoid parse errors)
	for USER_CONFIG in $(THINGINO_USER_JSON_FILES); do \
		[ -s "$$USER_CONFIG" ] && \
			$(HOST_DIR)/bin/jct "$(THINGINO_CORE_OUTPUT_FILE)" import "$$USER_CONFIG" || true; \
	done

	printf "thingino-core: finalized %s\n" $(THINGINO_CORE_OUTPUT_FILE) 1>&2
endef
THINGINO_CORE_TARGET_FINALIZE_HOOKS += THINGINO_CORE_MERGE_THINGINO_JSON

$(eval $(generic-package))
