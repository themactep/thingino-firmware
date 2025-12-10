################################################################################
#
# go overrides for Thingino
#
################################################################################

ifeq ($(BR2_PACKAGE_THINGINO_GO),y)

# Use the upstream 1.25.3 release everywhere.
override GO_VERSION = 1.25.3

# Building Go >= 1.24 requires a Go 1.22.6+ bootstrap compiler.
override HOST_GO_SRC_DEPENDENCIES = \
	host-go-bootstrap-stage4 \
	$(HOST_GO_DEPENDENCIES_CGO)

# Point the bootstrap step to our stage4 toolchain.
override HOST_GO_SRC_MAKE_ENV = \
	GO111MODULE=off \
	GOCACHE=$(HOST_GO_HOST_CACHE) \
	GOROOT_BOOTSTRAP=$(HOST_GO_BOOTSTRAP_STAGE4_ROOT) \
	GOROOT_FINAL=$(HOST_GO_ROOT) \
	GOROOT="$(@D)" \
	GOBIN="$(@D)/bin" \
	GOOS=linux \
	CC=$(HOSTCC_NOCCACHE) \
	CXX=$(HOSTCXX_NOCCACHE) \
	CGO_ENABLED=$(HOST_GO_CGO_ENABLED) \
	$(HOST_GO_SRC_CROSS_ENV)

endif
