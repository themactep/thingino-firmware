THINGINO_FFMPEG_VERSION = 6f1ab828d3da168d28c65c03b80ad89a61c19d06
THINGINO_FFMPEG_SITE = https://github.com/FFmpeg/FFmpeg.git
THINGINO_FFMPEG_SITE_METHOD = git
THINGINO_FFMPEG_LICENSE = LGPL-2.1+, libjpeg license
THINGINO_FFMPEG_LICENSE_FILES = LICENSE.md COPYING.LGPLv2.1

# Install to staging only for LIGHTNVR (needed for CMake pkg-config)
ifeq ($(BR2_PACKAGE_THINGINO_FFMPEG_LIGHTNVR),y)
THINGINO_FFMPEG_INSTALL_STAGING = YES
THINGINO_FFMPEG_DEPENDENCIES += host-pkgconf
else
THINGINO_FFMPEG_INSTALL_STAGING = NO
THINGINO_FFMPEG_DEPENDENCIES += host-pkgconf host-upx
endif

# Helper variables for list manipulation
empty :=
space := $(empty) $(empty)
comma := ,

# Our curated "disable everything" macro - lighter version of FFmpeg's --disable-everything
THINGINO_FFMPEG_DISABLE_JUNK = \
	--disable-encoders \
	--disable-decoders \
	--disable-hwaccels \
	--disable-parsers \
	--disable-indevs \
	--disable-outdevs \
	--disable-filters \
	--disable-bsfs \
	--disable-demuxers \
	--disable-muxers \
	--disable-protocols \
	--disable-debug \
	--disable-doc \
	--disable-htmlpages \
	--disable-manpages \
	--disable-podpages \
	--disable-txtpages \
	--disable-ffplay \
	--disable-ffprobe \
	--disable-iconv \
	--disable-zlib \
	--disable-swscale \
	--enable-avdevice \
	--disable-cuda \
	--disable-cuda-llvm

# Base configuration options
THINGINO_FFMPEG_CONF_OPTS = \
	--prefix=/usr \
	--enable-mipsfpu \
	--enable-mipsdspr2 \
	--disable-msa \
	--enable-cross-compile \
	--enable-gpl \
	--enable-version3 \
	--enable-avformat \
	--enable-avcodec \
	--enable-network \
	--enable-static \
	--enable-ffmpeg \
	--enable-protocol=file \
	--enable-protocol=tcp \
	--enable-protocol=udp

# Apply different base configurations based on variant
ifneq ($(BR2_PACKAGE_THINGINO_FFMPEG_DEV),y)
# For IPC and NVR: use minimal configuration with selective enabling
THINGINO_FFMPEG_CONF_OPTS += \
	$(THINGINO_FFMPEG_DISABLE_JUNK) \
	--enable-muxer=segment \
	--disable-shared \
	--extra-cflags="-Os -flto-partition=none" \
	--extra-ldflags="-z max-page-size=0x1000 -flto-partition=none -Wl,--gc-sections" \
	--disable-libx264 \
	--disable-libx265 \
	--disable-libdav1d \
	--disable-libvpx \
	--disable-libopus
else
# For DEV: use different optimization and enable more features by default
THINGINO_FFMPEG_CONF_OPTS += \
	$(THINGINO_FFMPEG_DISABLE_JUNK) \
	--extra-cflags="-O2" \
	--extra-ldflags="-z max-page-size=0x1000"
endif

# Disable swresample unless OPUS is selected
ifneq ($(BR2_PACKAGE_THINGINO_FFMPEG_OPUS),y)
THINGINO_FFMPEG_CONF_OPTS += --disable-swresample
endif

# Initialize codec/format lists
THINGINO_FFMPEG_PARSERS =
THINGINO_FFMPEG_DEMUXERS = rtsp
THINGINO_FFMPEG_MUXERS =
THINGINO_FFMPEG_ENCODERS =
THINGINO_FFMPEG_DECODERS =
THINGINO_FFMPEG_FILTERS =
THINGINO_FFMPEG_INDEVS =

# IPC (IP Camera) configuration - minimal for RTSP recording
ifeq ($(BR2_PACKAGE_THINGINO_FFMPEG_IPC),y)
THINGINO_FFMPEG_CONF_OPTS += --enable-swresample
THINGINO_FFMPEG_PARSERS += h264 opus
THINGINO_FFMPEG_DECODERS += opus h264 wrapped_avframe
THINGINO_FFMPEG_ENCODERS += aac rawvideo
THINGINO_FFMPEG_MUXERS += mp4 rtsp avi mpegts
THINGINO_FFMPEG_FILTERS += color testsrc testsrc2 smptebars rgbtestsrc
THINGINO_FFMPEG_INDEVS += lavfi
THINGINO_FFMPEG_DEPENDENCIES += thingino-opus
endif

# NVR (Network Video Recorder) configuration - extended features
ifeq ($(BR2_PACKAGE_THINGINO_FFMPEG_NVR),y)
THINGINO_FFMPEG_CONF_OPTS += --enable-swresample --enable-swscale
THINGINO_FFMPEG_PARSERS += h264 hevc aac opus
THINGINO_FFMPEG_DEMUXERS += mov m4a
THINGINO_FFMPEG_MUXERS += mp4 opus
THINGINO_FFMPEG_ENCODERS += aac
THINGINO_FFMPEG_DECODERS += h264 hevc aac opus
THINGINO_FFMPEG_DEPENDENCIES += thingino-opus
endif

# LIGHTNVR configuration - enables staging installation for CMake
ifeq ($(BR2_PACKAGE_THINGINO_FFMPEG_LIGHTNVR),y)
# Enable swscale for lightNVR (required by CMake configuration)
THINGINO_FFMPEG_CONF_OPTS += --enable-swscale --enable-swresample
# Add additional codecs and formats needed by lightNVR
THINGINO_FFMPEG_PARSERS += h264 hevc aac opus
THINGINO_FFMPEG_DEMUXERS += mov m4a rtsp
THINGINO_FFMPEG_MUXERS += mp4 opus
THINGINO_FFMPEG_ENCODERS += aac
THINGINO_FFMPEG_DECODERS += h264 hevc aac opus
THINGINO_FFMPEG_DEPENDENCIES += thingino-opus
endif

# DEV (Development/Maximum Features) configuration - all features enabled
ifeq ($(BR2_PACKAGE_THINGINO_FFMPEG_DEV),y)
# Override the disable-everything approach for DEV build
THINGINO_FFMPEG_DISABLE_JUNK = \
	--disable-debug \
	--disable-doc \
	--disable-htmlpages \
	--disable-manpages \
	--disable-podpages \
	--disable-txtpages \
	--enable-avdevice \
	--disable-cuda \
	--disable-cuda-llvm

# Enable maximum features for DEV configuration
THINGINO_FFMPEG_CONF_OPTS += \
	--enable-swresample \
	--enable-swscale \
	--enable-avfilter \
	--enable-pthreads \
	--disable-shared \
	--enable-static \
	--enable-ffplay \
	--enable-ffprobe \
	--enable-encoders \
	--enable-decoders \
	--enable-hwaccels \
	--enable-parsers \
	--enable-demuxers \
	--enable-muxers \
	--enable-protocols \
	--enable-filters \
	--enable-bsfs \
	--enable-indevs \
	--enable-outdevs \
	--enable-zlib \
	--enable-iconv

# Add dependencies for maximum features
THINGINO_FFMPEG_DEPENDENCIES += thingino-opus zlib
endif

# Add specific codec/format options only for non-DEV configurations
# DEV configuration uses --enable-all flags instead of individual components
ifneq ($(BR2_PACKAGE_THINGINO_FFMPEG_DEV),y)

# Add parser options if any parsers are enabled
ifneq ($(THINGINO_FFMPEG_PARSERS),)
THINGINO_FFMPEG_CONF_OPTS += --enable-parser=$(subst $(space),$(comma),$(strip $(THINGINO_FFMPEG_PARSERS)))
endif

# Add demuxer options
ifneq ($(THINGINO_FFMPEG_DEMUXERS),)
THINGINO_FFMPEG_CONF_OPTS += --enable-demuxer=$(subst $(space),$(comma),$(strip $(THINGINO_FFMPEG_DEMUXERS)))
endif

# Add muxer options if any muxers are enabled
ifneq ($(THINGINO_FFMPEG_MUXERS),)
THINGINO_FFMPEG_CONF_OPTS += --enable-muxer=$(subst $(space),$(comma),$(strip $(THINGINO_FFMPEG_MUXERS)))
endif

# Add encoder options if any encoders are enabled
ifneq ($(THINGINO_FFMPEG_ENCODERS),)
THINGINO_FFMPEG_CONF_OPTS += --enable-encoder=$(subst $(space),$(comma),$(strip $(THINGINO_FFMPEG_ENCODERS)))
endif

# Add decoder options if any decoders are enabled
ifneq ($(THINGINO_FFMPEG_DECODERS),)
THINGINO_FFMPEG_CONF_OPTS += --enable-decoder=$(subst $(space),$(comma),$(strip $(THINGINO_FFMPEG_DECODERS)))
endif

# Add filter options if any filters are enabled
ifneq ($(THINGINO_FFMPEG_FILTERS),)
THINGINO_FFMPEG_CONF_OPTS += --enable-filter=$(subst $(space),$(comma),$(strip $(THINGINO_FFMPEG_FILTERS)))
endif

# Add input device options if any input devices are enabled
ifneq ($(THINGINO_FFMPEG_INDEVS),)
THINGINO_FFMPEG_CONF_OPTS += --enable-indev=$(subst $(space),$(comma),$(strip $(THINGINO_FFMPEG_INDEVS)))
endif

endif

# Default to --cpu=generic for MIPS architecture, in order to avoid a
# warning from ffmpeg's configure script.
ifeq ($(BR2_mips)$(BR2_mipsel)$(BR2_mips64)$(BR2_mips64el),y)
THINGINO_FFMPEG_CONF_OPTS += --cpu=mips32r2
# MSA disabled due to type incompatibility errors with GCC 7.2.0
# THINGINO_FFMPEG_CONF_OPTS += --enable-msa
else ifneq ($(GCC_TARGET_CPU),)
THINGINO_FFMPEG_CONF_OPTS += --cpu="$(GCC_TARGET_CPU)"
else ifneq ($(GCC_TARGET_ARCH),)
THINGINO_FFMPEG_CONF_OPTS += --cpu="$(GCC_TARGET_ARCH)"
endif

THINGINO_FFMPEG_CFLAGS = $(TARGET_CFLAGS)

ifeq ($(BR2_TOOLCHAIN_HAS_GCC_BUG_85180),y)
THINGINO_FFMPEG_CONF_OPTS += --disable-optimizations
THINGINO_FFMPEG_CFLAGS += -O0
endif

THINGINO_FFMPEG_CONF_ENV += CFLAGS="$(THINGINO_FFMPEG_CFLAGS)"

# Override THINGINO_FFMPEG_CONFIGURE_CMDS: FFmpeg does not support --target and others
define THINGINO_FFMPEG_CONFIGURE_CMDS
	(cd $(THINGINO_FFMPEG_SRCDIR) && rm -rf config.cache && \
	$(TARGET_CONFIGURE_OPTS) \
	$(TARGET_CONFIGURE_ARGS) \
	$(THINGINO_FFMPEG_CONF_ENV) \
	./configure \
		--enable-cross-compile \
		--cross-prefix=$(TARGET_CROSS) \
		--sysroot=$(STAGING_DIR) \
		--host-cc="$(HOSTCC)" \
		--arch=$(BR2_ARCH) \
		--target-os="linux" \
		--pkg-config="$(PKG_CONFIG_HOST_BINARY)" \
		$(THINGINO_FFMPEG_CONF_OPTS) \
	)
endef

define THINGINO_FFMPEG_REMOVE_EXAMPLE_SRC_FILES
	rm -rf $(TARGET_DIR)/usr/share/ffmpeg/examples
endef
THINGINO_FFMPEG_POST_INSTALL_TARGET_HOOKS += THINGINO_FFMPEG_REMOVE_EXAMPLE_SRC_FILES

define THINGINO_FFMPEG_UPX_INSTALL
		$(HOST_DIR)/bin/upx --best --lzma $(TARGET_DIR)/usr/bin/ffmpeg
endef

ifneq ($(BR2_PACKAGE_THINGINO_FFMPEG_LIGHTNVR),y)
THINGINO_FFMPEG_POST_INSTALL_TARGET_HOOKS += THINGINO_FFMPEG_UPX_INSTALL
endif

$(eval $(autotools-package))
