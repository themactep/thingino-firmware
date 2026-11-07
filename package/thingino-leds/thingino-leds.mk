THINGINO_LEDS_VERSION = 1.0
THINGINO_LEDS_SITE_METHOD = local
THINGINO_LEDS_SITE = $(THINGINO_LEDS_PKGDIR)/src
THINGINO_LEDS_MODULE_MAKE_OPTS = KSRC=$(LINUX_DIR)

# led_<c>=<gpio>,<active_low> for every colour whose GPIO is >= 0
thingino_leds_comma := ,
thingino_leds_arg = $(if $(filter-out -1,$(BR2_THINGINO_LED_$(1)_GPIO)),led_$(2)=$(BR2_THINGINO_LED_$(1)_GPIO)$(thingino_leds_comma)$(if $(BR2_THINGINO_LED_$(1)_ACTIVE_LOW),1,0))
THINGINO_LEDS_ARGS = $(strip \
	$(call thingino_leds_arg,B,b) $(call thingino_leds_arg,G,g) \
	$(call thingino_leds_arg,R,r) $(call thingino_leds_arg,W,w) \
	$(call thingino_leds_arg,Y,y) $(call thingino_leds_arg,V,v))

TARGET_MODULES_PATH = $(TARGET_DIR)/usr/lib/modules/$(KERNEL_VERSION)$(call qstrip,$(LINUX_CONFIG_LOCALVERSION))
define THINGINO_LEDS_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0644 $(@D)/thingino-leds.ko \
		$(TARGET_MODULES_PATH)/extra/thingino-leds.ko
	$(INSTALL) -m 0755 -d $(TARGET_DIR)/etc/modules.d
	$(if $(THINGINO_LEDS_ARGS),echo "thingino-leds $(THINGINO_LEDS_ARGS)" > $(TARGET_DIR)/etc/modules.d/40-leds)
endef

$(eval $(kernel-module))
$(eval $(generic-package))
