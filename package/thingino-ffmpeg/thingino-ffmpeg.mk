################################################################################
#
# thingino-ffmpeg
#
################################################################################

THINGINO_FFMPEG_VERSION = 7.0
THINGINO_FFMPEG_SOURCE = ffmpeg-$(THINGINO_FFMPEG_VERSION).tar.xz
THINGINO_FFMPEG_SITE = http://ffmpeg.org/releases

THINGINO_FFMPEG_INSTALL_STAGING = NO

THINGINO_FFMPEG_LICENSE = LGPL-2.1+, libjpeg license
THINGINO_FFMPEG_LICENSE_FILES = LICENSE.md COPYING.LGPLv2.1

THINGINO_FFMPEG_CONF_OPTS = \
	--prefix=/usr \
	--disable-everything \
	--disable-x86asm --disable-w32threads --disable-os2threads --disable-alsa --disable-appkit \
	--disable-avfoundation --disable-bzlib --disable-coreimage --disable-iconv --disable-libxcb \
	--disable-libxcb-shm --disable-libxcb-xfixes --disable-libxcb-shape --disable-lzma \
	--disable-asm --disable-sndio --disable-sdl2 --disable-xlib --disable-zlib --disable-amf \
	--disable-audiotoolbox --disable-cuda --disable-cuvid --disable-d3d11va --disable-dxva2 \
	--disable-nvdec --disable-nvenc --disable-v4l2-m2m --disable-vaapi --disable-vdpau --disable-videotoolbox \
	--disable-avdevice --disable-swscale --disable-postproc --disable-doc --disable-runtime-cpudetect \
	--disable-bsfs --disable-iconv --disable-ffprobe --enable-gpl --enable-version3 --enable-pthreads \
	\
	--disable-swresample \
	--disable-avdevice \
	--disable-filters \
	--disable-encoders \
	--disable-decoders --enable-decoder=h264,hevc \
	--disable-muxers --enable-muxer=flv,rtsp \
	--disable-demuxers --enable-demuxer=h264,rtsp \
	--disable-parsers --enable-parser=h264,hevc \
	--disable-protocols --enable-protocol=file,rtmp,tcp \
	--disable-programs --enable-ffmpeg --enable-small

THINGINO_FFMPEG_DEPENDENCIES += host-pkgconf

# Default to --cpu=generic for MIPS architecture, in order to avoid a
# warning from ffmpeg's configure script.
ifeq ($(BR2_mips)$(BR2_mipsel)$(BR2_mips64)$(BR2_mips64el),y)
THINGINO_FFMPEG_CONF_OPTS += --cpu=mips32r2
THINGINO_FFMPEG_CONF_OPTS += --enable-msa
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

$(eval $(autotools-package))
