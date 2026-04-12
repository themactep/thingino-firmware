#!/bin/bash

#
# RootFS helper
#

BOOTLOADER=$(echo $BR2_PACKAGE_THINGINO_UBOOT_BOARDNAME | tr -d '"')

# Preset the hostname
IMAGE_ID=${CAMERA}
HOSTNAME=ing-$(echo $IMAGE_ID | awk -F '_' '{print $1 "-" $2}')
echo "$HOSTNAME" > ${TARGET_DIR}/etc/hostname
sed -i "/^127.0.1.1/c127.0.1.1\t$HOSTNAME" ${TARGET_DIR}/etc/hosts

cd $BR2_EXTERNAL
GIT_BRANCH=$(git branch | grep ^* | awk '{print $2}')
GIT_HASH=$(git show -s --format=%H)
GIT_TIME=$(TZ=UTC0 git show --quiet --date='format-local:%Y-%m-%d %H:%M:%S +0000' --format="%cd")
BUILD_TIME="$(env -u SOURCE_DATE_EPOCH TZ=UTC date '+%Y-%m-%d %H:%M:%S %z')"
BUILD_ID="${GIT_BRANCH}+${GIT_HASH:0:7}, ${BUILD_TIME}"
COMMIT_ID="${GIT_BRANCH}+${GIT_HASH:0:7}, ${GIT_TIME}"
cd -

if grep -q "BR2_TOOLCHAIN_USES_GLIBC=y" $BR2_CONFIG; then
	TOOLCHAIN="glibc"
elif grep -q "BR2_TOOLCHAIN_USES_UCLIBC=y" $BR2_CONFIG; then
	TOOLCHAIN="uclibc"
elif grep -q "BR2_TOOLCHAIN_USES_MUSL=y" $BR2_CONFIG; then
	TOOLCHAIN="musl"
else
	echo "Unknown"
fi

#
# Create the /etc/os-release file
#

# Take care of dropbear
rm ${TARGET_DIR}/etc/dropbear
mkdir -p ${TARGET_DIR}/etc/dropbear

FILE=${TARGET_DIR}/usr/lib/os-release

# Create a temporary file
tmpfile=$(mktemp)

# Prefix exiting buildroot entries
sed 's/^/BUILDROOT_/' $FILE > $tmpfile

# Add Thingino entries
echo "NAME=Thingino
ID=thingino
VERSION=\"1 (Ciao)\"
VERSION_ID=1
VERSION_CODENAME=ciao
PRETTY_NAME=\"Thingino 1 (Ciao)\"
ID_LIKE=buildroot
CPE_NAME=\"cpe:/o:thinginoproject:thingino:1\"
LOGO=thingino-logo-icon
ANSI_COLOR=\"1;34\"
HOME_URL=\"https://thingino.com/\"
ARCHITECTURE=mips
TOOLCHAIN=${TOOLCHAIN}
SOC=${SOC_FAMILY}
SOC_ARCH=${SOC_ARCH}
IMAGE_ID=${IMAGE_ID}
BUILD_ID=\"${BUILD_ID}\"
BUILD_TIME=\"${BUILD_TIME}\"
COMMIT_ID=\"${COMMIT_ID}\"
BOOTLOADER=${BOOTLOADER}
HOSTNAME=${HOSTNAME}
TIME_STAMP=$(date +%s)" | tee $FILE

# Append the rest of the file
cat $tmpfile | tee -a $FILE

# Remove the temporary file
rm $tmpfile

# Adjust dropbear init script order
if [ -f "${TARGET_DIR}/etc/init.d/S50dropbear" ]; then
	mv ${TARGET_DIR}/etc/init.d/S50dropbear ${TARGET_DIR}/etc/init.d/S30dropbear
fi

# Toolchain specific fixes
rm -f ${TARGET_DIR}/usr/bin/ldd
echo '#!/bin/sh
LD_TRACE_LOADED_OBJECTS=1 exec "$@"' > ${TARGET_DIR}/usr/bin/ldd && chmod +x ${TARGET_DIR}/usr/bin/ldd

# Resolve the real on-disk lib directory: with merged-usr rootfs, /lib is a
# symlink to /usr/lib. Operate on /usr/lib directly so we never accidentally
# convert the symlink to a real directory or create broken literal-glob
# symlinks when the pattern fails to expand.
if [ -L "${TARGET_DIR}/lib" ] || [ ! -d "${TARGET_DIR}/lib" ]; then
	LIB_DIR="${TARGET_DIR}/usr/lib"
else
	LIB_DIR="${TARGET_DIR}/lib"
fi

if grep -q "^BR2_TOOLCHAIN_USES_MUSL=y" $BR2_CONFIG >/dev/null; then
	if [ -e "${LIB_DIR}/libc.so" ]; then
		ln -srf "${LIB_DIR}/libc.so" "${LIB_DIR}/ld-uClibc.so.0"
	fi
fi

if grep -q "^BR2_TOOLCHAIN_USES_UCLIBC=y" $BR2_CONFIG >/dev/null; then
	for libuclibc in "${LIB_DIR}"/libuClibc-*.so; do
		[ -e "$libuclibc" ] || continue
		ln -srf "$libuclibc" "${LIB_DIR}/libpthread.so.0"
		ln -srf "$libuclibc" "${LIB_DIR}/libdl.so.0"
		ln -srf "$libuclibc" "${LIB_DIR}/libm.so.0"
		break
	done
fi

if grep -q "^BR2_TOOLCHAIN_USES_GLIBC=y" $BR2_CONFIG >/dev/null; then
	if [ -e "${LIB_DIR}/libc.so.6" ]; then
		ln -srf "${LIB_DIR}/libc.so.6" "${LIB_DIR}/libpthread.so.0"
	fi
fi

#
# Remove unnecessary files
#

if [ -f "${TARGET_DIR}/lib/libconfig.so" ]; then
	rm -vf ${TARGET_DIR}/lib/libconfig.so*
fi

if [ -f "${TARGET_DIR}/lib/libstdc++.so.6.0.34-gdb.py" ]; then
	rm -vf ${TARGET_DIR}/lib/libstdc++.so.6.0.34-gdb.py
fi

if grep -q ^BR2_PACKAGE_EXFAT_UTILS $BR2_CONFIG >/dev/null; then
	rm -vf ${TARGET_DIR}/usr/sbin/exfatattrib
	rm -vf ${TARGET_DIR}/usr/sbin/dumpexfat
	rm -vf ${TARGET_DIR}/usr/sbin/exfatlabel
	rm -vf ${TARGET_DIR}/etc/network/nfs_check
fi
