WOLFSSH_VERSION = 1.4.19
WOLFSSH_SITE = $(call github,wolfSSL,wolfssh,v$(WOLFSSH_VERSION)-stable)
WOLFSSH_INSTALL_STAGING = YES

WOLFSSH_LICENSE = GPL-2.0+
WOLFSSH_LICENSE_FILES = LICENSING
# From git
WOLFSSH_AUTORECONF = YES
WOLFSSH_DEPENDENCIES = host-pkgconf thingino-wolfssl


ifeq ($(BR2_PACKAGE_WOLFSSH_ENABLE_INLINE),y)
	WOLFSSH_CONF_OPTS += --enable-inline
else
	WOLFSSH_CONF_OPTS += --disable-inline
endif

ifeq ($(BR2_PACKAGE_WOLFSSH_ENABLE_EXAMPLES),y)
	WOLFSSH_CONF_OPTS += --enable-examples
else
	WOLFSSH_CONF_OPTS += --disable-examples
endif

ifeq ($(BR2_PACKAGE_WOLFSSH_ENABLE_KEYGEN),y)
	WOLFSSH_CONF_OPTS += --enable-keygen
else
	WOLFSSH_CONF_OPTS += --disable-keygen
endif

ifeq ($(BR2_PACKAGE_WOLFSSH_ENABLE_SCP),y)
	WOLFSSH_CONF_OPTS += --enable-scp
else
	WOLFSSH_CONF_OPTS += --disable-scp
endif

ifeq ($(BR2_PACKAGE_WOLFSSH_ENABLE_SFTP),y)
	WOLFSSH_CONF_OPTS += --enable-sftp
else
	WOLFSSH_CONF_OPTS += --disable-sftp
endif

ifeq ($(BR2_PACKAGE_WOLFSSH_ENABLE_SSHD),y)
	WOLFSSH_CONF_OPTS += --enable-sshd
else
	WOLFSSH_CONF_OPTS += --disable-sshd
endif

ifeq ($(BR2_PACKAGE_WOLFSSH_ENABLE_SSHCLIENT),y)
	WOLFSSH_CONF_OPTS += --enable-sshclient
else
	WOLFSSH_CONF_OPTS += --disable-sshclient
endif

ifeq ($(BR2_PACKAGE_WOLFSSH_ENABLE_FWD),y)
	WOLFSSH_CONF_OPTS += --enable-fwd
else
	WOLFSSH_CONF_OPTS += --disable-fwd
endif

ifeq ($(BR2_PACKAGE_WOLFSSH_ENABLE_TERM),y)
	WOLFSSH_CONF_OPTS += --enable-term
else
	WOLFSSH_CONF_OPTS += --disable-term
endif

ifeq ($(BR2_PACKAGE_WOLFSSH_ENABLE_SHELL),y)
	WOLFSSH_CONF_OPTS += --enable-shell
else
	WOLFSSH_CONF_OPTS += --disable-shell
endif

ifeq ($(BR2_PACKAGE_WOLFSSH_ENABLE_AGENT),y)
	WOLFSSH_CONF_OPTS += --enable-agent
else
	WOLFSSH_CONF_OPTS += --disable-agent
endif

ifeq ($(BR2_PACKAGE_WOLFSSH_ENABLE_CERTS),y)
	WOLFSSH_CONF_OPTS += --enable-certs CPPFLAGS=-DWOLFSSH_NO_FPKI
else
	WOLFSSH_CONF_OPTS += --disable-certs
endif

ifeq ($(BR2_PACKAGE_WOLFSSH_ENABLE_SMALLSTACK),y)
	WOLFSSH_CONF_OPTS += --enable-smallstack
else
	WOLFSSH_CONF_OPTS += --disable-smallstack
endif

ifeq ($(BR2_PACKAGE_WOLFSSH_ENABLE_ALL),y)
	WOLFSSH_CONF_OPTS += --enable-all
else
	WOLFSSH_CONF_OPTS += --disable-all
endif

ifeq ($(BR2_PACKAGE_WOLFSSH_ENABLE_DISTRO),y)
	WOLFSSH_CONF_OPTS += --enable-distro
else
	WOLFSSH_CONF_OPTS += --disable-distro
endif


ifeq ($(BR2_PACKAGE_WOLFSSH_ENABLE_CURVE25519),y)
	WOLFSSH_CONF_OPTS += --enable-wolfssh --enable-curve25519
endif

ifeq ($(BR2_PACKAGE_WOLFSSH_ENABLE_KYBER),y)
	WOLFSSH_CONF_OPTS += --enable-wolfssh --enable-experimental --enable-kyber
endif

$(eval $(autotools-package))
