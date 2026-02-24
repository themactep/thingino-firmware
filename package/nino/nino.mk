################################################################################
# nino
################################################################################

NINO_VERSION = 1a0ee5315423a0f24b71ec96d8bdcc5eda53ee5b
NINO_SITE = https://github.com/evanlin96069/nino
NINO_SITE_METHOD = git

NINO_LICENSE = BSD-2-Clause
NINO_LICENSE_FILES = LICENSE

# Uses CMake as its build system
NINO_SUPPORTS_IN_SOURCE_BUILD = NO

# Pre-generate resources/bundle.h using a host-built bundler and disable
# the in-tree bundler in CMake when cross-compiling.
# This avoids trying to run a target binary on the host during the build.
define NINO_GENERATE_BUNDLE
	$(HOSTCC) -O2 -o $(@D)/bundler $(@D)/resources/bundler.c
	$(@D)/bundler $(@D)/resources/bundle.h \
		$(@D)/resources/syntax/c.json \
		$(@D)/resources/syntax/cpp.json \
		$(@D)/resources/syntax/java.json \
		$(@D)/resources/syntax/json.json \
		$(@D)/resources/syntax/make.json \
		$(@D)/resources/syntax/python.json \
		$(@D)/resources/syntax/rust.json \
		$(@D)/resources/syntax/zig.json
	# Drop bundler targets and custom_command; keep using the pre-generated bundle.h
	sed -i \
		-e '/^add_executable(bundler /,/^)/d' \
		-e '/^set *(BUNDLER_BIN/d' \
		-e '/^add_custom_command[[:space:]]*(/,/^)/d' \
		$(@D)/CMakeLists.txt
endef
NINO_PRE_CONFIGURE_HOOKS += NINO_GENERATE_BUNDLE

$(eval $(cmake-package))

