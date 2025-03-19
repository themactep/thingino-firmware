THINGINO_FFMPEG_VERSION = 7.1.1
THINGINO_FFMPEG_SOURCE = ffmpeg-$(THINGINO_FFMPEG_VERSION).tar.xz
THINGINO_FFMPEG_SITE = http://ffmpeg.org/releases

ifeq ($(BR2_PACKAGE_THINGINO_FFMPEG_LIGHTNVR),y)
THINGINO_FFMPEG_INSTALL_STAGING = YES
else
THINGINO_FFMPEG_INSTALL_STAGING = NO
endif

THINGINO_FFMPEG_LICENSE = LGPL-2.1+, libjpeg license
THINGINO_FFMPEG_LICENSE_FILES = LICENSE.md COPYING.LGPLv2.1

THINGINO_FFMPEG_CONF_OPTS = \
	--prefix=/usr \
	--enable-mipsfpu \
	--enable-cross-compile \
	--disable-everything \
	--disable-cuda \
	--disable-cuda-llvm \
	--enable-gpl \
	--enable-version3 \
	--enable-ffmpeg \
	--enable-avformat \
	--enable-avcodec \
	--enable-network \
	--enable-protocol=tcp \
	--enable-protocol=udp \
	--enable-protocol=file \
	--enable-parser=h264,hevc,aac,opus \
	--enable-demuxer=rtsp,mov,m4a \
	--enable-muxer=mp4,opus \
	--enable-muxer=segment \
	--disable-doc \
	--disable-podpages \
	--disable-htmlpages \
	--disable-manpages \
	--disable-txtpages \
	--disable-iconv \
	--disable-zlib \
	--disable-swscale \
	--disable-avdevice \
	--disable-postproc \
	--disable-debug \
	--disable-ffprobe \
	--enable-small \
	--disable-encoders \
	--disable-decoders \
	--disable-runtime-cpudetect \
	--disable-swresample \
	--extra-cflags="-Os -flto-partition=none" \
	--extra-cxxflags="-Os -flto-partition=none" \
	--extra-ldflags="-z max-page-size=0x1000 -flto-partition=none -Wl,--gc-sections"

# Override with lightnvr-specific options if that package is selected
ifeq ($(BR2_PACKAGE_THINGINO_FFMPEG_LIGHTNVR),y)
THINGINO_FFMPEG_CONF_OPTS = \
	--prefix=/usr \
	--enable-mipsfpu \
	--disable-asm \
	--enable-cross-compile \
	--disable-everything \
	--enable-small \
	--enable-shared \
	--enable-gpl \
	--enable-version3 \
	--enable-avformat \
	--enable-avcodec \
	--enable-swscale \
	--enable-network \
	--enable-protocol=http,tcp,udp,file,rtsp,rtp \
	--enable-parser=h264,hevc,aac,opus \
	--enable-demuxer=rtsp,rtp,mov,m4a,mpegts,h264 \
	--enable-muxer=mp4,opus,mpegts,hls,segment \
	--enable-filter=scale \
	--enable-bsf=aac_adtstoasc,h264_mp4toannexb,hevc_mp4toannexb \
	--enable-decoder=h264,aac,hevc \
	--disable-static \
	--disable-cuda \
	--disable-cuda-llvm \
	--disable-doc \
	--disable-podpages \
	--disable-htmlpages \
	--disable-manpages \
	--disable-txtpages \
	--disable-iconv \
	--disable-zlib \
	--disable-avdevice \
	--disable-postproc \
	--disable-debug \
	--disable-ffprobe \
	--disable-ffmpeg \
	--disable-encoders \
	--disable-runtime-cpudetect \
	--disable-swresample \
	--extra-cflags="-Os" \
	--extra-cxxflags="-Os" \
	--extra-cflags="-Os -flto-partition=none" \
	--extra-cxxflags="-Os -flto-partition=none" \
	--extra-ldflags="-z max-page-size=0x1000 -flto-partition=none -Wl,--gc-sections"
endif

ifeq ($(BR2_PACKAGE_THINGINO_FFMPEG_LIGHTNVR),y)
THINGINO_FFMPEG_DEPENDENCIES += host-pkgconf
else
THINGINO_FFMPEG_DEPENDENCIES += host-pkgconf host-upx
endif

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

define THINGINO_FFMPEG_UPX_INSTALL
		$(HOST_DIR)/bin/upx --best --lzma $(TARGET_DIR)/usr/bin/ffmpeg
endef

ifneq ($(BR2_PACKAGE_THINGINO_FFMPEG_LIGHTNVR),y)
THINGINO_FFMPEG_POST_INSTALL_TARGET_HOOKS += THINGINO_FFMPEG_UPX_INSTALL
endif

$(eval $(autotools-package))
