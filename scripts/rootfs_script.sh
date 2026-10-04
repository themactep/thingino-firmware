#!/bin/bash
# shellcheck disable=SC2086
# All variables are BR2_* or TARGET_DIR from Buildroot make environment;
# dep_check.sh guarantees paths are free of spaces and special characters.
#
# RootFS helper
#

set -euo pipefail

BOOTLOADER=$(echo ${BR2_TARGET_UBOOT_BOARD_DEFCONFIG:-$BR2_TARGET_UBOOT_BOARDNAME} | tr -d '"')

# Preset the hostname
IMAGE_ID=${CAMERA}
IMAGE_NAME=$(sed -n 's/^# NAME: //p' "$BR2_EXTERNAL/${CAMERA_SUBDIR}/${CAMERA}/${CAMERA}_defconfig" 2>/dev/null | head -1)
HOSTNAME=ing-$(echo $IMAGE_ID | awk -F '_' '{print $1 "-" $2}')
echo "$HOSTNAME" > ${TARGET_DIR}/etc/hostname
sed -i "/^127.0.1.1/c127.0.1.1\t$HOSTNAME" ${TARGET_DIR}/etc/hosts

# NAND keeps the U-Boot env in the UBI "uboot-env" volume, so fw_printenv/setenv
# must target that volume instead of a raw MTD offset (the NOR default).
if grep -q "^BR2_THINGINO_FLASH_NAND=y" "$BR2_CONFIG"; then
	printf '/dev/ubi0:uboot-env 0x0 0x10000 0x10000\n' > "${TARGET_DIR}/etc/fw_env.config"
elif grep -q '^BR2_TARGET_UBOOT_VERSION="20[2-9][0-9]\.' "$BR2_CONFIG" &&
	[ "$(cat "${TARGET_DIR}/etc/fw_env.config" 2>/dev/null)" = "/dev/mtd1 0x0 0x8000" ]; then
	# The modern NOR U-Boot (2026.07: T20/T32/T40/T41) keeps a 64 KiB env
	# (CONFIG_ENV_SIZE=0x10000, CONFIG_ENV_SECT_SIZE=0x10000, 64k "env"
	# partition). The overlay default 0x8000 is right for U-Boot 2013.07 only:
	# on this one fw_setenv would write a 32 KiB env whose CRC U-Boot rejects,
	# silently dropping every user variable. A board overlay that already sets
	# its own fw_env.config (the Wyze T20s) is left alone.
	printf '/dev/mtd1 0x0 0x10000 0x10000\n' > "${TARGET_DIR}/etc/fw_env.config"
fi

# U-Boot 2026.07: never let fw_setenv replace an environment that fails its CRC.
# When the stored env is unreadable (blank, or written with the wrong size by an
# older image), fw_printenv/fw_setenv fall back to the tool's own 3-variable
# default and fw_setenv would then store THAT as a valid env - U-Boot would take
# it as real (bootcmd=bootp...) and the camera would no longer boot from flash,
# where an invalid env makes U-Boot use its built-in defaults and boot. The real
# tool moves to /usr/libexec/uboot-env, the old names become a guard that refuses
# on "Bad CRC" (FW_SETENV_FORCE=1 overrides).
if grep -q '^BR2_TARGET_UBOOT_VERSION="20[2-9][0-9]\.' "$BR2_CONFIG" &&
	[ -L "${TARGET_DIR}/usr/sbin/fw_setenv" ]; then
	install -d "${TARGET_DIR}/usr/libexec/uboot-env"
	ln -sf ../../sbin/fw_printenv "${TARGET_DIR}/usr/libexec/uboot-env/fw_setenv"
	for d in usr/sbin sbin; do
		[ -L "${TARGET_DIR}/${d}/fw_setenv" ] || continue
		rm -f "${TARGET_DIR}/${d}/fw_setenv"
		cat > "${TARGET_DIR}/${d}/fw_setenv" <<'GUARD_EOF'
#!/bin/sh
# Refuse to write the U-Boot environment while the stored one fails its CRC (see
# scripts/rootfs_script.sh). FW_SETENV_FORCE=1 overrides.
cfg=""
prev=""
for a in "$@"; do
	if [ "$prev" = "-c" ] || [ "$prev" = "--config" ]; then cfg="$a"; fi
	prev="$a"
done
if [ -z "$FW_SETENV_FORCE" ]; then
	if [ -n "$cfg" ]; then
		w=$(/usr/sbin/fw_printenv -c "$cfg" bootcmd 2>&1 >/dev/null)
	else
		w=$(/usr/sbin/fw_printenv bootcmd 2>&1 >/dev/null)
	fi
	case "$w" in
	*"Bad CRC"*)
		echo "fw_setenv: the stored U-Boot environment fails its CRC - refusing to write (it would replace U-Boot's built-in defaults with a minimal environment). FW_SETENV_FORCE=1 overrides." >&2
		logger -t fw_setenv "refused: stored U-Boot environment has a bad CRC" 2>/dev/null
		exit 1
		;;
	esac
fi
exec /usr/libexec/uboot-env/fw_setenv "$@"
GUARD_EOF
		chmod 755 "${TARGET_DIR}/${d}/fw_setenv"
	done
fi

cd $BR2_EXTERNAL
GIT_BRANCH=$(git branch | grep '^\*' | awk '{print $2}')
GIT_HASH=$(git show -s --format=%H)
GIT_TIME=$(TZ=UTC0 git show --quiet --date='format-local:%Y-%m-%d %H:%M:%S UTC' --format="%cd")
BUILD_TIME="$(env -u SOURCE_DATE_EPOCH TZ=UTC date '+%Y-%m-%d %H:%M:%S UTC')"
BUILD_ID="${GIT_BRANCH}+${GIT_HASH:0:7}, ${BUILD_TIME}"
COMMIT_ID="${GIT_BRANCH}+${GIT_HASH:0:7}, ${GIT_TIME}"
cd -

if grep -q "^BR2_TOOLCHAIN_USES_GLIBC=y" "$BR2_CONFIG"; then
	LIBC="glibc"
elif grep -q "^BR2_TOOLCHAIN_USES_UCLIBC=y" "$BR2_CONFIG"; then
	LIBC="uclibc"
elif grep -q "^BR2_TOOLCHAIN_USES_MUSL=y" "$BR2_CONFIG"; then
	LIBC="musl"
else
	LIBC="unknown"
fi

if grep -q "^BR2_TOOLCHAIN_EXTERNAL=y" "$BR2_CONFIG"; then
	TOOLCHAIN_TYPE="external"
elif grep -q "^BR2_TOOLCHAIN_BUILDROOT=y" "$BR2_CONFIG"; then
	TOOLCHAIN_TYPE="buildroot"
else
	TOOLCHAIN_TYPE="unknown"
fi

# Derived from the Buildroot config rather than assumed. /etc/os-release is read
# at runtime -- `soc -a` reports from it and the web UI displays it -- so this
# value is user-visible and should describe what was actually built.
if grep -q "^BR2_arm=y\|^BR2_armeb=y" "$BR2_CONFIG"; then
	ARCHITECTURE="arm"
elif grep -q "^BR2_aarch64=y\|^BR2_aarch64_be=y" "$BR2_CONFIG"; then
	ARCHITECTURE="aarch64"
elif grep -q "^BR2_mips=y\|^BR2_mipsel=y\|^BR2_mips64=y\|^BR2_mips64el=y" "$BR2_CONFIG"; then
	ARCHITECTURE="mips"
else
	ARCHITECTURE="unknown"
fi

TOOLCHAIN_GCC=$(sed -rn 's/^BR2_GCC_VERSION="([^"]+)"/\1/p' "$BR2_CONFIG" | tail -n1)
if [ -z "$TOOLCHAIN_GCC" ]; then
	TOOLCHAIN_GCC=$(sed -rn 's/^BR2_TOOLCHAIN_(EXTERNAL|BUILDROOT)_GCC_([0-9]+)=y$/\2/p' "$BR2_CONFIG" | tail -n1)
fi
if [ -z "$TOOLCHAIN_GCC" ]; then
	TOOLCHAIN_GCC="unknown"
fi

#
# Create the /etc/os-release file
#

# Take care of dropbear
rm -f ${TARGET_DIR}/etc/dropbear
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
ARCHITECTURE=${ARCHITECTURE}
LIBC=${LIBC}
TOOLCHAIN=${LIBC}
TOOLCHAIN_TYPE=${TOOLCHAIN_TYPE}
TOOLCHAIN_GCC=${TOOLCHAIN_GCC}
SOC=${SOC_FAMILY}
SOC_ARCH=${SOC_ARCH}
IMAGE_ID=${IMAGE_ID}
IMAGE_NAME=\"${IMAGE_NAME}\"
BUILD_ID=\"${BUILD_ID}\"
BUILD_TIME=\"${BUILD_TIME}\"
COMMIT_ID=\"${COMMIT_ID}\"
BOOTLOADER=${BOOTLOADER}
HOSTNAME=${HOSTNAME}
BUILD_TIMESTAMP=$(date +%s)" | tee $FILE

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

rm -vf ${TARGET_DIR}/lib/libstdc++.so.6.0.*-gdb.py 2>/dev/null

if ! grep -q ^BR2_THINGINO_LIBSTDCPP=y $BR2_CONFIG 2>/dev/null; then
	rm -vf ${TARGET_DIR}/lib/libstdc++.so*
	rm -vf ${TARGET_DIR}/usr/lib/libstdc++.so*
fi

if grep -q ^BR2_PACKAGE_EXFAT_UTILS $BR2_CONFIG >/dev/null; then
	rm -vf ${TARGET_DIR}/usr/sbin/exfatattrib
	rm -vf ${TARGET_DIR}/usr/sbin/dumpexfat
	rm -vf ${TARGET_DIR}/usr/sbin/exfatlabel
	rm -vf ${TARGET_DIR}/etc/network/nfs_check
fi

# BusyBox is built with long options enabled (CONFIG_LONG_OPTS=y in
# package/busybox/busybox.config), so scripts/check-busybox-lopts.sh no longer
# applies to the generated init scripts.
