################################################################################
#
# thingino-snmpd - shadow package for the Thingino mini-snmpd integration
#
################################################################################

# The daemon is built by Buildroot's mini-snmpd package; the Thingino
# additions live in mini-snmpd-override.mk. This wrapper only pulls the
# upstream package in when thingino-snmpd is selected.
THINGINO_SNMPD_DEPENDENCIES = mini-snmpd

$(eval $(virtual-package))
