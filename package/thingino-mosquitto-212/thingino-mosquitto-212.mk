################################################################################
#
# thingino-mosquitto-212 - shadow package to tweak mosquitto defaults
#
################################################################################

# Ensure our target/host wrappers trigger the upstream package.
THINGINO_MOSQUITTO_212_DEPENDENCIES = mosquitto
HOST_THINGINO_MOSQUITTO_212_DEPENDENCIES = host-mosquitto

$(eval $(virtual-package))
$(eval $(host-virtual-package))
