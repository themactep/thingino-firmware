################################################################################
#
# thingino-mosquitto - shadow package to tweak mosquitto defaults
#
################################################################################

# Stick to the Buildroot mosquitto implementation but pin our preferred source.
override MOSQUITTO_VERSION = 2.0.22
override MOSQUITTO_SITE = https://sources.buildroot.net/mosquitto

# Ensure our target/host wrappers trigger the upstream package.
THINGINO_MOSQUITTO_DEPENDENCIES = mosquitto
HOST_THINGINO_MOSQUITTO_DEPENDENCIES = host-mosquitto

$(eval $(virtual-package))
$(eval $(host-virtual-package))
