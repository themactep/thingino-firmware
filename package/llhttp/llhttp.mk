LLHTTP_VERSION = 9.2.1
LLHTTP_SITE = https://github.com/nodejs/llhttp/archive/refs/tags/release
LLHTTP_SOURCE = v$(LLHTTP_VERSION).tar.gz

LLHTTP_LICENSE = MIT
LLHTTP_LICENSE_FILES = LICENSE-MIT

LLHTTP_INSTALL_STAGING = YES

$(eval $(cmake-package))
