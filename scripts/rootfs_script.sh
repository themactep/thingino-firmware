#!/bin/bash

#
# RootFS helper
#

BOOTLOADER=$(echo $BR2_PACKAGE_THINGINO_UBOOT_BOARDNAME | tr -d '"')

# Preset the hostname
IMAGE_ID=$(echo $BR2_CONFIG | awk -F '/' '{print $(NF-1)}')
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
SOC_ARCH=${INGENIC_ARCH}
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

# Generate thingino.config
${BR2_EXTERNAL}/scripts/thingino_config_gen.sh "${TARGET_DIR}/etc/thingino.config" "$BR2_EXTERNAL" "$CAMERA_SUBDIR" "$CAMERA"

# Adjust dropbear init script order
if [ -f "${TARGET_DIR}/etc/init.d/S50dropbear" ]; then
	mv ${TARGET_DIR}/etc/init.d/S50dropbear ${TARGET_DIR}/etc/init.d/S30dropbear
fi

# Toolchain specific fixes
echo '#!/bin/sh
LD_TRACE_LOADED_OBJECTS=1 exec "$@"' > ${TARGET_DIR}/usr/bin/ldd && chmod +x ${TARGET_DIR}/usr/bin/ldd

if grep -q "^BR2_TOOLCHAIN_USES_MUSL=y" $BR2_CONFIG >/dev/null; then
	ln -srf ${TARGET_DIR}/lib/libc.so ${TARGET_DIR}/lib/ld-uClibc.so.0
	ln -srf ${TARGET_DIR}/lib/libc.so ${TARGET_DIR}/usr/bin/ldd
fi

if grep -q "^BR2_TOOLCHAIN_USES_UCLIBC=y" $BR2_CONFIG >/dev/null; then
	ln -srf ${TARGET_DIR}/lib/libuClibc*.so ${TARGET_DIR}/lib/libpthread.so.0
	ln -srf ${TARGET_DIR}/lib/libuClibc*.so ${TARGET_DIR}/lib/libdl.so.0
	ln -srf ${TARGET_DIR}/lib/libuClibc*.so ${TARGET_DIR}/lib/libm.so.0
fi

if grep -q "^BR2_TOOLCHAIN_USES_GLIBC=y" $BR2_CONFIG >/dev/null; then
	ln -srf ${TARGET_DIR}/lib/libc.so.6 ${TARGET_DIR}/lib/libpthread.so.0
fi

#
# Remove unnecessary files
#

if [ -f "${TARGET_DIR}/lib/libconfig.so" ]; then
	rm -vf ${TARGET_DIR}/lib/libconfig.so*
fi

if [ -f "${TARGET_DIR}/lib/libstdc++.so.6.0.33-gdb.py" ]; then
	rm -vf ${TARGET_DIR}/lib/libstdc++.so.6.0.33-gdb.py
fi

if grep -q ^BR2_PACKAGE_EXFAT_UTILS $BR2_CONFIG >/dev/null; then
	rm -vf ${TARGET_DIR}/usr/sbin/exfatattrib
	rm -vf ${TARGET_DIR}/usr/sbin/dumpexfat
	rm -vf ${TARGET_DIR}/usr/sbin/exfatlabel
	rm -vf ${TARGET_DIR}/etc/network/nfs_check
fi

#
# Remove unnecessary wolfSSL programs to save space
# Keep only essential tools for SSL certificate management
#
if grep -q ^BR2_PACKAGE_THINGINO_WOLFSSL_EXAMPLES $BR2_CONFIG >/dev/null; then
	echo "Removing unnecessary wolfSSL example programs to save space..."

	# Remove benchmarking & testing tools (if they exist)
	rm -vf ${TARGET_DIR}/usr/bin/benchmark
	rm -vf ${TARGET_DIR}/usr/bin/testsuite
	rm -vf ${TARGET_DIR}/usr/bin/unit_test

	# Remove development & demo tools
	rm -vf ${TARGET_DIR}/usr/bin/client
	rm -vf ${TARGET_DIR}/usr/bin/server
	rm -vf ${TARGET_DIR}/usr/bin/echoclient
	rm -vf ${TARGET_DIR}/usr/bin/echoserver
	rm -vf ${TARGET_DIR}/usr/bin/sctp-client
	rm -vf ${TARGET_DIR}/usr/bin/sctp-server

	# Remove specialized crypto tools (keep ssl_server2 for cert generation)
	rm -vf ${TARGET_DIR}/usr/bin/tls_bench
	rm -vf ${TARGET_DIR}/usr/bin/crypto_bench

	# Keep essential wolfSSL tools for certificate generation and testing
	# ssl_server2 - for certificate generation and SSL testing
	# These are needed for our certificate generation scripts

	echo "Kept essential wolfSSL tools: ssl_server2 (for certificate generation)"
fi

#
# Fix ustream-ssl library conflicts
# Remove any conflicting ustream-ssl libraries from overlay to ensure
# the correct wolfSSL-based library is used
#
if [ -f "${TARGET_DIR}/overlay/usr/lib/libustream-ssl.so" ]; then
	echo "Removing conflicting ustream-ssl library from overlay..."
	rm -vf "${TARGET_DIR}/overlay/usr/lib/libustream-ssl.so"
fi

#
# Legacy mbedTLS cleanup (for compatibility with mixed builds)
# This section can be removed once fully migrated to wolfSSL
#
if grep -q ^BR2_PACKAGE_MBEDTLS_PROGRAMS $BR2_CONFIG >/dev/null; then
	echo "Removing legacy mbedTLS programs (compatibility cleanup)..."

	# Remove all mbedTLS tools since we're using wolfSSL
	rm -vf ${TARGET_DIR}/usr/bin/cert_app
	rm -vf ${TARGET_DIR}/usr/bin/cert_write
	rm -vf ${TARGET_DIR}/usr/bin/gen_key
	rm -vf ${TARGET_DIR}/usr/bin/ssl_server2

	echo "Removed legacy mbedTLS tools (using wolfSSL instead)"
fi
