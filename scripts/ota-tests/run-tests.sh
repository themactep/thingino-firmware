#!/bin/bash
# shellcheck disable=SC1091,SC2017,SC2034,SC2329
# SC1091: scenarios.sh is sourced from this directory.
# SC2017: a/b*c is intentional integer ceil-division for 64 KiB alignment.
# SC2034/SC2329: globals and helpers cross functions/scenarios by design.
# OTA fitting tests: boot a QEMU x86_64 VM with a file-backed MTD flash,
# run the real flash-ota script against synthetic (or real) images, then
# verify where the bytes landed and what the U-Boot env mtdparts says.
#
# Usage: run-tests.sh [scenario_name ...]   (default: all)
#
# Requires the environment from build.sh (kernel, busybox, initramfs).

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
OUTROOT="${THINGINO_OUTPUT_ROOT_DIR:-$REPO/output}"
SCRATCH="$OUTROOT/ota-tests"
KBUILD="$SCRATCH/kbuild"
KERNEL="$KBUILD/arch/x86/boot/bzImage"
INITRD="$SCRATCH/initramfs.cpio.gz"
FLASH="$SCRATCH/flash.img"
QEMU_BIN="${QEMU_BIN:-qemu-system-x86_64}"

# Real images for the REAL_IMAGES scenario (the .34 cinnado build)
IMG_DIR="${IMG_DIR:-$OUTROOT/ciao/cinnado_d1_t31l_sc2336_atbm6031-3.10.14-uclibc-192.168.88.34/images}"

source "$HERE/scenarios.sh"
ALL_SCENARIOS="scenario_fit_normal scenario_exact_fit scenario_rootfs_grew scenario_rootfs_shrunk scenario_rootfs_only scenario_too_big scenario_no_all scenario_non_adjacent scenario_kernel scenario_kernel_real scenario_boot scenario_real_images"

PASS=0
FAIL=0

[ -f "$KERNEL" ] || {
	echo "kernel missing - run build.sh first" >&2
	exit 1
}
[ -f "$INITRD" ] || {
	echo "initramfs missing - run build.sh first" >&2
	exit 1
}

# --- helpers ---------------------------------------------------------------

octal() { # hex byte -> tr octal escape (GNU coreutils tr also takes \xHH)
	case "$1" in
		aa) printf '\252' ;;
		55) printf '\125' ;;
		ff) printf '\377' ;;
		33) printf '\063' ;;
		11) printf '\021' ;;
		22) printf '\042' ;;
		44) printf '\104' ;;
		00) printf '\000' ;;
		*) printf '\252' ;;
	esac
}

fill_region() { # file offset_k size_k hexbyte
	dd if=/dev/zero bs=1024 count="$3" 2>/dev/null | tr '\000' "$(octal "$4")" |
		dd of="$1" bs=1024 seek="$2" conv=notrunc 2>/dev/null
}

region_md5() { # file offset_k size_k
	dd if="$1" bs=1024 skip="$2" count="$3" 2>/dev/null | md5sum | cut -d' ' -f1
}

region_md5_bytes() { # file offset_bytes len_bytes
	dd if="$1" bs=1024 skip=$(($2 / 1024)) count=$((($2 + $3 + 1023) / 1024)) 2>/dev/null |
		head -c "$3" | md5sum | cut -d' ' -f1
}

pattern_md5() { # size_k hexbyte
	dd if=/dev/zero bs=1024 count="$1" 2>/dev/null | tr '\000' "$(octal "$2")" | md5sum | cut -d' ' -f1
}

log_has() { # substring
	grep -qF -- "$1" "$SCRATCH/run-$NAME.log"
}

assert_region() { # label offset_k size_k expected_md5
	local got
	got=$(region_md5 "$FLASH" "$2" "$3")
	if [ "$got" = "$4" ]; then
		echo "  PASS: $1"
		PASS=$((PASS + 1))
	else
		echo "  FAIL: $1 (got $got want $4)"
		FAIL=$((FAIL + 1))
	fi
}

assert_cmd() { # label cmd...
	local label=$1
	shift
	if "$@"; then
		echo "  PASS: $label"
		PASS=$((PASS + 1))
	else
		echo "  FAIL: $label"
		FAIL=$((FAIL + 1))
	fi
}

# Parse a mtdparts string into the layout globals.
read_layout() {
	OLD_PARTS=()
	OLD_ROOTFS_OFF=-1
	OLD_DATA_OFF=-1
	OLD_ROOTFS_K=0
	OLD_DATA_K=0
	OLD_ROOTFS_N=-1
	OLD_DATA_N=-1
	OLD_KERNEL_N=-1
	OLD_BOOT_N=-1
	OLD_ENV_N=-1
	local rest="${1#*:}" tok name size i=0 off=0
	IFS=',' read -r -a toks <<<"$rest"
	for tok in "${toks[@]}"; do
		name=$(sed -n 's/.*(\(.*\))$/\1/p' <<<"$tok")
		size=$(sed -n 's/^\([0-9]*\)k.*/\1/p' <<<"$tok")
		OLD_PARTS+=("$size:$name")
		case "$name" in
			rootfs)
				OLD_ROOTFS_K=$size
				OLD_ROOTFS_OFF=$off
				OLD_ROOTFS_N=$i
				;;
			data)
				OLD_DATA_K=$size
				OLD_DATA_OFF=$off
				OLD_DATA_N=$i
				;;
			kernel) OLD_KERNEL_N=$i ;;
			boot) OLD_BOOT_N=$i ;;
			env) OLD_ENV_N=$i ;;
		esac
		off=$((off + size))
		i=$((i + 1))
	done
}

env_mtdparts() { # -> current mtdparts value in flash.img env (no name= prefix)
	printf '%s\n' "$FLASH 0x40000 0x8000 0x10000" >"$SCRATCH/fw_env.config"
	fw_printenv -c "$SCRATCH/fw_env.config" mtdparts 2>/dev/null | cut -d= -f2-
}

# --- flash setup -----------------------------------------------------------

setup_flash() {
	echo "== setting up $FLASH (old layout)"
	rm -f "$FLASH"
	# whole flash erased (0xFF)
	dd if=/dev/zero bs=1024 count=8192 2>/dev/null | tr '\000' "$(octal ff)" >"$FLASH"
	fill_region "$FLASH" 0 256 11    # boot
	fill_region "$FLASH" 320 64 22   # backup
	fill_region "$FLASH" 384 1600 33 # kernel
	[ "${RESERVED_K:-0}" -gt 0 ] && fill_region "$FLASH" $((OLD_ROOTFS_OFF + OLD_ROOTFS_K)) "$RESERVED_K" 44
	# env blob with the OLD mtdparts at the env partition (chip offset 256k)
	printf 'mtdparts=%s\n' "$OLD_MTDPARTS" >"$SCRATCH/env.txt"
	mkenvimage -s 0x8000 -o "$SCRATCH/env.bin" "$SCRATCH/env.txt" >/dev/null
	dd if="$SCRATCH/env.bin" of="$FLASH" bs=1024 seek=256 conv=notrunc 2>/dev/null

	# the old firmware rootfs: a tiny squashfs holding the env tools, so
	# that like on a real camera they vanish when the partition is erased
	if [ "$MODE" = rootfs ] && [ -f "$SCRATCH/fakeroot.squashfs" ]; then
		dd if="$SCRATCH/fakeroot.squashfs" of="$FLASH" bs=1024 seek="$OLD_ROOTFS_OFF" conv=notrunc 2>/dev/null
	fi
}

# --- VM run ----------------------------------------------------------------

bake_real_images() {
	# repack the initramfs with the real images baked in
	local dir="$SCRATCH/initramfs-real"
	rm -rf "$dir"
	cp -a "$SCRATCH/initramfs" "$dir"
	[ -f "$IMG_DIR/rootfs.squashfs" ] && cp "$IMG_DIR/rootfs.squashfs" "$dir/images/rootfs.bin"
	[ -f "$IMG_DIR/data.jffs2" ] && cp "$IMG_DIR/data.jffs2" "$dir/images/data.bin"
	[ -f "$IMG_DIR/uImage" ] && cp "$IMG_DIR/uImage" "$dir/images/uImage"
	[ -f "$IMG_DIR/u-boot-env.bin" ] && cp "$IMG_DIR/u-boot-env.bin" "$dir/images/u-boot-env.bin"
	[ -f "$IMG_DIR/u-boot-lzo-with-spl.bin" ] && cp "$IMG_DIR/u-boot-lzo-with-spl.bin" "$dir/images/u-boot.bin"
	(cd "$dir" && find . -print0 | cpio --null -o -H newc 2>/dev/null | gzip -9) >"$SCRATCH/initramfs-real.cpio.gz"
	echo "$SCRATCH/initramfs-real.cpio.gz"
}

run_vm() {
	local initrd="$INITRD"
	[ -n "${REAL_IMAGES:-}" ] && initrd=$(bake_real_images)
	local accel=()
	if [ -e /dev/kvm ]; then
		accel=(-accel kvm -cpu host)
	else
		accel=(-accel tcg)
	fi
	local cmdline="console=ttyS0 panic=-1"
	cmdline="$cmdline mtdparts=$OLD_MTDPARTS"
	cmdline="$cmdline t_mode=$MODE t_rootfs=${ROOTFS_K:-0} t_data=${DATA_K:-0}"
	cmdline="$cmdline t_kernel=${KERNEL_K:-0} t_boot=${BOOT_K:-0} t_env=${ENV_K:-0}"
	cmdline="$cmdline t_fill=${FILL:-aa} t_filld=${FILLD:-55} t_fille=33"

	echo "== booting VM (scenario $NAME)"
	timeout 120 "$QEMU_BIN" -machine pc "${accel[@]}" -m 64M -smp 2 \
		-kernel "$KERNEL" -initrd "$initrd" -append "$cmdline" \
		-drive file="$FLASH",if=none,id=fl,format=raw \
		-device virtio-blk-pci,drive=fl \
		-nographic -no-reboot >"$SCRATCH/run-$NAME.log" 2>&1
	local rc=$?
	echo "== qemu exited ($rc)"
}

# --- verification ----------------------------------------------------------

verify() {
	local expected_new_rootfs expected_new_data
	if [ "$MODE" = rootfs ]; then
		expected_new_rootfs=$(((${ROOTFS_K:-0} * 1024 + 65535) / 65536 * 64))
		if [ -n "${REAL_IMAGES:-}" ]; then
			expected_new_rootfs=$((($(stat -c%s "$IMG_DIR/rootfs.squashfs") + 65535) / 65536 * 64))
		fi
		expected_new_data=$((OLD_ROOTFS_K + OLD_DATA_K - expected_new_rootfs))
	fi

	echo "== verifying $NAME (mode=$MODE expect=${EXPECT:-flash})"
	assert_cmd "log: /proc/mtd shows partitions" log_has '"rootfs"'

	case "$MODE" in
		rootfs)
			local data_write_off=$((OLD_ROOTFS_OFF + expected_new_rootfs))

			local exp_rootfs_md5 exp_data_md5 exp_rootfs_bytes exp_data_bytes
			if [ -n "${REAL_IMAGES:-}" ]; then
				exp_rootfs_md5=$(md5sum "$IMG_DIR/rootfs.squashfs" | cut -d' ' -f1)
				exp_data_md5=$(md5sum "$IMG_DIR/data.jffs2" | cut -d' ' -f1)
				exp_rootfs_bytes=$(stat -c%s "$IMG_DIR/rootfs.squashfs")
				exp_data_bytes=$(stat -c%s "$IMG_DIR/data.jffs2")
			else
				exp_rootfs_md5=$(pattern_md5 "${ROOTFS_K:-0}" "${FILL:-aa}")
				exp_data_md5=$(pattern_md5 "${DATA_K:-0}" "${FILLD:-55}")
				exp_rootfs_bytes=$((${ROOTFS_K:-0} * 1024))
				exp_data_bytes=$((${DATA_K:-0} * 1024))
			fi

			case "$EXPECT" in
				flash)
					assert_cmd "log: rootfs written via dd" log_has "Writing rootfs"
					if [ "$exp_data_bytes" -gt 0 ]; then
						assert_cmd "log: data written via dd" log_has "Writing data"
					fi
					if [ "$exp_rootfs_bytes" -gt 0 ]; then
						assert_region "rootfs image at $OLD_ROOTFS_OFF" "$OLD_ROOTFS_OFF" "$((exp_rootfs_bytes / 1024))" "$exp_rootfs_md5"
					fi
					if [ "$exp_data_bytes" -gt 0 ]; then
						assert_region "data image at $data_write_off (new data partition)" "$data_write_off" "$((exp_data_bytes / 1024))" "$exp_data_md5"
						# tail of the data partition beyond the image stays erased
						local tail_k=$((expected_new_data - exp_data_bytes / 1024))
						if [ "$tail_k" -gt 0 ]; then
							assert_region "data partition tail erased" "$((data_write_off + exp_data_bytes / 1024))" "$tail_k" "$(pattern_md5 "$tail_k" ff)"
						fi
					fi
					if [ "$expected_new_rootfs" -eq "$OLD_ROOTFS_K" ]; then
						assert_cmd "env mtdparts unchanged" [ "$(env_mtdparts)" = "$OLD_MTDPARTS" ]
					else
						assert_cmd "log: mtdparts update announced" log_has "Updating U-Boot mtdparts to"
						local exp_env
						exp_env=$(printf '%s\n' "$OLD_MTDPARTS" |
							sed "s/,[0-9]*k(rootfs),[0-9]*k(data)/,${expected_new_rootfs}k(rootfs),${expected_new_data}k(data)/")
						assert_cmd "env mtdparts updated to $exp_env" [ "$(env_mtdparts)" = "$exp_env" ]
					fi
					;;
				error)
					assert_cmd "log: error message" log_has "$ERR_MSG"
					assert_cmd "flash unchanged (nothing written)" \
						[ "$(md5sum "$FLASH" | cut -d' ' -f1)" = "$flash_before" ]
					assert_cmd "env mtdparts unchanged" [ "$(env_mtdparts)" = "$OLD_MTDPARTS" ]
					;;
			esac

			assert_region "boot region untouched" 0 256 "$(pattern_md5 256 11)"
			assert_region "backup region untouched" 320 64 "$(pattern_md5 64 22)"
			assert_region "kernel region untouched" 384 1600 "$(pattern_md5 1600 33)"
			;;
		kernel)
			assert_cmd "log: kernel flash" log_has "Flashing kernel from /tmp/kernel.bin to /dev/mtd$OLD_KERNEL_N"
			if [ -n "${REAL_IMAGES:-}" ] && [ -f "$IMG_DIR/uImage" ]; then
				assert_region_bytes "kernel image at 393216 (384K)" 393216 "$(stat -c%s "$IMG_DIR/uImage")" "$(md5sum "$IMG_DIR/uImage" | cut -d' ' -f1)"
			else
				assert_region "kernel image at 384" 384 "${KERNEL_K:-0}" "$(pattern_md5 "${KERNEL_K:-0}" "${FILL:-aa}")"
			fi
			assert_region "boot region untouched" 0 256 "$(pattern_md5 256 11)"
			assert_region "backup region untouched" 320 64 "$(pattern_md5 64 22)"
			assert_cmd "env mtdparts unchanged" [ "$(env_mtdparts)" = "$OLD_MTDPARTS" ]
			;;
		boot)
			assert_cmd "log: boot flash" log_has "Flashing boot from /tmp/boot.bin to /dev/mtd$OLD_BOOT_N"
			assert_cmd "log: env flash" log_has "Flashing env from /tmp/env.bin to /dev/mtd$OLD_ENV_N"
			assert_region_bytes "boot image at 0" 0 "$(stat -c%s "$IMG_DIR/u-boot-lzo-with-spl.bin")" "$(md5sum "$IMG_DIR/u-boot-lzo-with-spl.bin" | cut -d' ' -f1)"
			assert_region_bytes "env blob at env partition (262144)" 262144 "$(stat -c%s "$IMG_DIR/u-boot-env.bin")" "$(md5sum "$IMG_DIR/u-boot-env.bin" | cut -d' ' -f1)"
			local baked_env
			printf '%s\n' "$IMG_DIR/u-boot-env.bin 0x0 0x8000 0x10000 1" >"$SCRATCH/fw_env.envbin"
			baked_env=$(fw_printenv -c "$SCRATCH/fw_env.envbin" mtdparts 2>/dev/null | cut -d= -f2-)
			assert_cmd "env mtdparts now the new layout ($baked_env)" [ "$(env_mtdparts)" = "$baked_env" ]
			assert_region "kernel region untouched" 384 1600 "$(pattern_md5 1600 33)"
			assert_region "backup region untouched" 320 64 "$(pattern_md5 64 22)"
			;;
	esac
}

assert_region_bytes() { # label offset_bytes len_bytes expected_md5
	local got
	got=$(region_md5_bytes "$FLASH" "$2" "$3")
	if [ "$got" = "$4" ]; then
		echo "  PASS: $1"
		PASS=$((PASS + 1))
	else
		echo "  FAIL: $1 (got $got want $4)"
		FAIL=$((FAIL + 1))
	fi
}

# --- main ------------------------------------------------------------------

run_scenario() {
	# reset per-scenario defaults
	NAME=
	OLD_MTDPARTS=
	MODE=rootfs
	ROOTFS_K=0
	DATA_K=0
	KERNEL_K=0
	BOOT_K=0
	ENV_K=0
	FILL=aa
	FILLD=55
	EXPECT=normal
	ERR_MSG=
	RESERVED_K=0
	REAL_IMAGES=
	"$1"

	if [ -n "$REAL_IMAGES" ] && [ ! -f "$IMG_DIR/rootfs.squashfs" ] && [ ! -f "$IMG_DIR/uImage" ] && [ ! -f "$IMG_DIR/u-boot-lzo-with-spl.bin" ]; then
		echo "SKIP: $NAME (real images not found in $IMG_DIR)"
		return
	fi

	read_layout "$OLD_MTDPARTS"
	flash_before=$(md5sum "$FLASH" 2>/dev/null | cut -d' ' -f1)
	[ -n "$flash_before" ] || flash_before="(no flash yet)"

	echo
	echo "============================================================"
	echo "SCENARIO: $NAME"
	echo "  old layout: $OLD_MTDPARTS"
	echo "  new: rootfs=${ROOTFS_K}K data=${DATA_K}K mode=$MODE expect=$EXPECT"
	echo "============================================================"
	setup_flash
	flash_before=$(md5sum "$FLASH" | cut -d' ' -f1)
	run_vm
	verify
}

SCENARIOS=("$@")
[ ${#SCENARIOS[@]} -eq 0 ] && read -r -a SCENARIOS <<<"$ALL_SCENARIOS"

for s in "${SCENARIOS[@]}"; do
	if declare -F "$s" >/dev/null; then
		run_scenario "$s"
	else
		echo "unknown scenario: $s" >&2
		exit 1
	fi
done

echo
echo "=================== SUMMARY ==================="
echo "PASS: $PASS  FAIL: $FAIL"
[ "$FAIL" -eq 0 ] && echo "ALL TESTS PASSED" || echo "SOME TESTS FAILED"
exit $((FAIL > 0))
