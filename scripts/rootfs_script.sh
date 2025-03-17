#!/bin/bash

# get image id from the path to output
IMAGE_ID=$(echo $BR2_CONFIG | awk -F '/' '{print $(NF-1)}')
HOSTNAME=$(echo $IMAGE_ID | awk -F '_' '{print $1 "-" $2}')
BOOTLOADER=$(echo $BR2_PACKAGE_THINGINO_UBOOT_BOARDNAME | tr -d '"')

cd $BR2_EXTERNAL
GIT_BRANCH=$(git branch | grep ^* | awk '{print $2}')
GIT_HASH=$(git show -s --format=%H)
GIT_TIME=$(TZ=UTC0 git show --quiet --date='format-local:%Y-%m-%d %H:%M:%S +0000' --format="%cd")
BUILD_TIME="$(env -u SOURCE_DATE_EPOCH TZ=UTC date '+%Y-%m-%d %H:%M:%S %z')"
BUILD_ID="${GIT_BRANCH}+${GIT_HASH:0:7}, ${BUILD_TIME}"
COMMIT_ID="${GIT_BRANCH}+${GIT_HASH:0:7}, ${GIT_TIME}"
cd -

# Take care of dropbear
rm ${TARGET_DIR}/etc/dropbear
mkdir -p ${TARGET_DIR}/etc/dropbear

FILE=${TARGET_DIR}/usr/lib/os-release
# prefix exiting buildroot entries
tmpfile=$(mktemp)
sed 's/^/BUILDROOT_/' $FILE > $tmpfile
# create our own release file
{
	echo "NAME=Thingino"
	echo "ID=thingino"
	echo "VERSION=\"1 (Ciao)\""
	echo "VERSION_ID=1"
	echo "VERSION_CODENAME=ciao"
	echo "PRETTY_NAME=\"Thingino 1 (Ciao)\""
	echo "ID_LIKE=buildroot"
	echo "CPE_NAME=\"cpe:/o:thinginoproject:thingino:1\""
	echo "LOGO=thingino-logo-icon"
	echo "ANSI_COLOR=\"1;34\""
	echo "HOME_URL=\"https://thingino.com/\""
	echo "ARCHITECTURE=mips"
	echo "IMAGE_ID=${IMAGE_ID}"
	echo "BUILD_ID=\"${BUILD_ID}\""
	echo "BUILD_TIME=\"${BUILD_TIME}\""
	echo "COMMIT_ID=\"${COMMIT_ID}\""
	echo "BOOTLOADER=$BOOTLOADER"
	echo "HOSTNAME=ing-${HOSTNAME}"
	date +TIME_STAMP=%s
	cat $tmpfile
} > $FILE
rm $tmpfile

if [ -f "${TARGET_DIR}/lib/libconfig.so" ]; then
	rm -vf ${TARGET_DIR}/lib/libconfig.so*
fi

if [ -f "${TARGET_DIR}/lib/libstdc++.so.6.0.33-gdb.py" ]; then
	rm -vf ${TARGET_DIR}/lib/libstdc++.so.6.0.33-gdb.py
fi

if [ -f "${TARGET_DIR}/etc/init.d/S50dropbear" ]; then
	mv ${TARGET_DIR}/etc/init.d/S50dropbear ${TARGET_DIR}/etc/init.d/S30dropbear
fi

if grep -q ^BR2_TOOLCHAIN_USES_MUSL $BR2_CONFIG; then
	ln -srf ${TARGET_DIR}/lib/libc.so ${TARGET_DIR}/lib/ld-uClibc.so.0
	ln -srf ${TARGET_DIR}/lib/libc.so ${TARGET_DIR}/usr/bin/ldd
fi

if grep -q ^BR2_PACKAGE_EXFAT_UTILS $BR2_CONFIG; then
	rm -vf ${TARGET_DIR}/usr/sbin/exfatattrib
	rm -vf ${TARGET_DIR}/usr/sbin/dumpexfat
	rm -vf ${TARGET_DIR}/usr/sbin/exfatlabel
	rm -vf ${TARGET_DIR}/etc/network/nfs_check
fi
