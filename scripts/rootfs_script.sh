#!/bin/bash

# get image id from the path to output
IMAGE_ID=$(echo $BR2_CONFIG | awk -F '/' '{print $(NF-1)}')
HOSTNAME=$(echo $IMAGE_ID | awk -F '_' '{print $1 "-" $2}')

cd $BR2_EXTERNAL
GIT_BRANCH=$(git branch | grep ^* | awk '{print $2}')
GIT_HASH=$(git show -s --format=%H)
GIT_TIME=$(git show -s --format=%ci)
BUILD_ID="${GIT_BRANCH}+${GIT_HASH:0:7}, ${GIT_TIME}"
cd -

FILE=${TARGET_DIR}/usr/lib/os-release
# prefix exiting buildroot entires
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
