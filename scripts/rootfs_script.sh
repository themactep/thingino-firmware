#!/bin/bash

#NAME=Thingino
#VERSION=1
#ID=thingino
#VERSION_ID=1
#PRETTY_NAME="Thingino 1 (Ciao)"
#ANSI_COLOR="1;34"
#CPE_NAME="cpe:/o:thinginoproject:thingino:1"
#HOME_URL="https://thingino.com/"
#SUPPORT_URL="https://help.thingino.com/"
#BUG_REPORT_URL="https://issues.thingino.com/"
#PRIVACY_POLICY_URL="https://policy.thingino.com/"
#BUILD_ID=
#VARIANT="Ingenic T31 Edition"
#VARIANT_ID="ingenic_t31"

FILE=${TARGET_DIR}/usr/lib/os-release

GIT_BRANCH=$(git branch | grep ^* | awk '{print $2}')
GIT_HASH=$(git show -s --format=%H)
GIT_TIME=$(git show -s --format=%ci)

echo "GITHUB_VERSION=\"${GIT_BRANCH}+${GIT_HASH}, ${GIT_TIME}\"" >>${FILE}
date +TIME_STAMP=%s >>${FILE}

CONF="INGENIC_OSDRV_T30=y|LIBV4L=y|WEBRTC_AUDIO_PROCESSING=y|USES_GLIBC"
if ! grep -qP ${CONF} ${BR2_CONFIG}; then
	rm -f ${TARGET_DIR}/usr/lib/libstdc++*
fi

#if grep -q "USES_MUSL" ${BR2_CONFIG}; then
#  LIST=${BR2_EXTERNAL}/scripts/excludes/${SOC_MODEL}.list
#  test -e ${LIST} && xargs -a ${LIST} -I % rm -rf ${TARGET_DIR}/%
#
#  ln -sf libc.so ${TARGET_DIR}/lib/ld-uClibc.so.0
#  ln -sf ../../lib/libc.so ${TARGET_DIR}/usr/bin/ldd
#fi
