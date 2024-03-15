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

if grep -q "USES_MUSL" ${BR2_CONFIG}; then
#  LIST=${BR2_EXTERNAL}/scripts/excludes/${SOC_MODEL}.list
#  test -e ${LIST} && xargs -a ${LIST} -I % rm -rf ${TARGET_DIR}/%
  ln -srf ${TARGET_DIR}/lib/libc.so ${TARGET_DIR}/lib/ld-uClibc.so.0
  ln -srf ${TARGET_DIR}/lib/libc.so ${TARGET_DIR}/usr/bin/ldd
fi
