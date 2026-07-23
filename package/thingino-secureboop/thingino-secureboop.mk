################################################################################
#
# Thingino secure-boot bypass (secureboop)
#
# Modifies the locally-built U-Boot binary so it boots on locked-down
# Ingenic cameras.  Controlled by a single Buildroot config entry:
#   BR2_PACKAGE_THINGINO_SECUREBOOP=y
#
# SOC dispatch is handled inside the U-Boot post-build hook:
#   T31  – collision-based SPL forging (transplants a vendor signature)
#   T32  – INGE init-table injection
#   T40  – same mechanism, T40-specific addresses
#   T41  – same mechanism, T41-specific addresses
#
# No changes to the top-level Makefile are needed.
################################################################################

ifeq ($(BR2_TARGET_UBOOT)$(BR2_PACKAGE_THINGINO_SECUREBOOP)$(BR_BUILDING),yyy)

SECUREBOOP_DIR = $(BR2_EXTERNAL_THINGINO_PATH)/package/thingino-secureboop

# The U-Boot binary that Buildroot builds and installs.
# Thingino sets BR2_TARGET_UBOOT_FORMAT_CUSTOM_NAME in the core fragment.
SECUREBOOP_UBOOT_BIN = $(call qstrip,$(BR2_TARGET_UBOOT_FORMAT_CUSTOM_NAME))

# ---------------------------------------------------------------------------
# T31 helpers
# ---------------------------------------------------------------------------

# Resolve the reference SPL path: relative to the camera config directory.
SECUREBOOP_T31_REFERENCE_SPL_RAW = $(call qstrip,$(BR2_PACKAGE_THINGINO_SECUREBOOP_T31_REFERENCE_SPL))
ifneq ($(SECUREBOOP_T31_REFERENCE_SPL_RAW),)
ifneq ($(filter /%,$(SECUREBOOP_T31_REFERENCE_SPL_RAW)),)
SECUREBOOP_T31_REFERENCE_SPL = $(SECUREBOOP_T31_REFERENCE_SPL_RAW)
else
SECUREBOOP_T31_REFERENCE_SPL = $(BR2_EXTERNAL_THINGINO_PATH)/$(CAMERA_SUBDIR)/$(CAMERA)/$(SECUREBOOP_T31_REFERENCE_SPL_RAW)
endif
endif

SECUREBOOP_T31_NONCE = $(call qstrip,$(BR2_PACKAGE_THINGINO_SECUREBOOP_T31_NONCE_OFFSETS))
SECUREBOOP_T31_HASH_END = $(call qstrip,$(BR2_PACKAGE_THINGINO_SECUREBOOP_T31_HASH_END))

# ---------------------------------------------------------------------------
# Per-SOC hook bodies (shell, called from the dispatch hook below)
# ---------------------------------------------------------------------------

define THINGINO_SECUREBOOP_T31_FORGE
	@if [ -z "$(SECUREBOOP_T31_REFERENCE_SPL)" ]; then \
		echo "SECUREBOOP: T31 reference SPL not configured — skipping forge"; \
	elif [ ! -f "$(SECUREBOOP_T31_REFERENCE_SPL)" ]; then \
		echo "SECUREBOOP: reference SPL not found: $(SECUREBOOP_T31_REFERENCE_SPL)"; \
	else \
		echo "SECUREBOOP: forging T31 SPL…"; \
		$(SECUREBOOP_DIR)/t31_spl_forge.py \
			--reference "$(SECUREBOOP_T31_REFERENCE_SPL)" \
			--candidate "$(@D)/$(SECUREBOOP_UBOOT_BIN)" \
			--output "$(@D)/$(SECUREBOOP_UBOOT_BIN)" \
			--nonce-offset $(firstword $(SECUREBOOP_T31_NONCE)) \
			$(if $(word 2,$(SECUREBOOP_T31_NONCE)),--nonce-offset2 $(word 2,$(SECUREBOOP_T31_NONCE))) \
			$(if $(word 3,$(SECUREBOOP_T31_NONCE)),--nonce-offset3 $(word 3,$(SECUREBOOP_T31_NONCE))) \
			$(if $(word 4,$(SECUREBOOP_T31_NONCE)),--nonce-offset4 $(word 4,$(SECUREBOOP_T31_NONCE))) \
			$(if $(SECUREBOOP_T31_HASH_END),--hash-end $(SECUREBOOP_T31_HASH_END)) \
			--exponent auto \
			$(if $(BR2_JLEVEL),--workers $(BR2_JLEVEL)) \
			|| { echo "SECUREBOOP: T31 forge FAILED"; exit 1; }; \
		echo "SECUREBOOP: T31 forge OK"; \
	fi
endef

define THINGINO_SECUREBOOP_T32_BYPASS
	@echo "SECUREBOOP: injecting T32 init-table bypass…"
	@$(SECUREBOOP_DIR)/patch_t32_init_bypass.py \
		"$(@D)/$(SECUREBOOP_UBOOT_BIN)" \
		-o "$(@D)/$(SECUREBOOP_UBOOT_BIN)" \
		--force \
		|| { echo "SECUREBOOP: T32 bypass FAILED"; exit 1; }
	@echo "SECUREBOOP: T32 bypass OK"
endef

define THINGINO_SECUREBOOP_T40_BYPASS
	@echo "SECUREBOOP: injecting T40 init-table bypass…"
	@$(SECUREBOOP_DIR)/patch_t40_init_bypass.py \
		"$(@D)/$(SECUREBOOP_UBOOT_BIN)" \
		-o "$(@D)/$(SECUREBOOP_UBOOT_BIN)" \
		--force \
		|| { echo "SECUREBOOP: T40 bypass FAILED"; exit 1; }
	@echo "SECUREBOOP: T40 bypass OK"
endef

define THINGINO_SECUREBOOP_T41_BYPASS
	@echo "SECUREBOOP: injecting T41 init-table bypass…"
	@$(SECUREBOOP_DIR)/patch_t41_init_bypass.py \
		"$(@D)/$(SECUREBOOP_UBOOT_BIN)" \
		-o "$(@D)/$(SECUREBOOP_UBOOT_BIN)" \
		--force \
		|| { echo "SECUREBOOP: T41 bypass FAILED"; exit 1; }
	@echo "SECUREBOOP: T41 bypass OK"
endef

# ---------------------------------------------------------------------------
# Dispatch hook — runs after U-Boot build, before images are installed
# ---------------------------------------------------------------------------

define THINGINO_SECUREBOOP_HOOK
	$(if $(filter t31,$(BR2_SOC_FAMILY)),$(THINGINO_SECUREBOOP_T31_FORGE))
	$(if $(filter t32,$(BR2_SOC_FAMILY)),$(THINGINO_SECUREBOOP_T32_BYPASS))
	$(if $(filter t40,$(BR2_SOC_FAMILY)),$(THINGINO_SECUREBOOP_T40_BYPASS))
	$(if $(filter t41,$(BR2_SOC_FAMILY)),$(THINGINO_SECUREBOOP_T41_BYPASS))
endef

UBOOT_POST_BUILD_HOOKS += THINGINO_SECUREBOOP_HOOK

endif # BR2_TARGET_UBOOT && BR2_PACKAGE_THINGINO_SECUREBOOP && BR_BUILDING
