################################################################################
#
# nginx-wolfssl
#
################################################################################

NGINX_WOLFSSL_DEPENDENCIES += wolfssl nginx

BR2_PACKAGE_NGINX_CONF_OPTS += --with-wolfssl=/usr/local --with-http_ssl_module
BR2_PACKAGE_NGINX_DEPENDENCIES += wolfssl

BR2_PACKAGE_WOLFSSL_CONF_OPTS += --prefix=/usr/local --enable-nginx

$(eval $(generic-package))
