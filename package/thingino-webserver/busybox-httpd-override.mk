################################################################################
#
# busybox httpd config fragment for thingino-webserver
#
################################################################################

# When BusyBox httpd is selected as the web server, inject all required
# httpd feature flags into the BusyBox configuration.
ifeq ($(BR2_PACKAGE_THINGINO_WEBSERVER_BUSYBOX),y)
BUSYBOX_KCONFIG_FRAGMENT_FILES += $(BR2_EXTERNAL)/package/thingino-webserver/busybox-httpd.config
endif
