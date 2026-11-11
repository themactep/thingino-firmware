#!/bin/bash
# shellcheck disable=SC1091,SC2017,SC2034,SC2329
# SC1091: scenarios.sh is sourced from this directory.
# SC2017: a/b*c is intentional integer ceil-division for 64 KiB alignment.
# SC2034/SC2329: globals and helpers cross functions/scenarios by design.
# sysupgrade QEMU tests: boot an x86_64 VM with a file-backed MTD flash,
# run the real sysupgrade-stage2 (full) or flash-ota (single partition)
# against synthetic images, then verify where the bytes landed.
#
# Usage: run-tests.sh [scenario_name ...]   (default: all)
#
# Requires the environment from build.sh (kernel, busybox, initramfs).

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
OUTROOT="${THINGINO_OUTPUT_ROOT_DIR:-$REPO/output}"
SCRATCH="$OUTROOT/sysupgrade-tests"
OTA="$OUTROOT/ota-tests"
KERNEL="$OTA/kbuild/arch/x86/boot/bzImage"
INITRD="$SCRATCH/initramfs.cpio.gz"
FLASH="$SCRATCH/flash.img"
QEMU_BIN="${QEMU_BIN:-qemu-system-x86_64}"

source "$HERE/scenarios.sh"
# Profile used by the branch tests; must match the fake release fixture.
TEST_PROFILE="testcam_t31x_gc2053_atbm6031"
ALL_SCENARIOS="scenario_full_same scenario_full_shrink scenario_full_grow scenario_full_shrink_nobackup scenario_part_boot_same scenario_part_boot_shrink scenario_part_boot_grow scenario_part_kernel_same scenario_part_kernel_different scenario_part_rootfs_same scenario_part_rootfs_grow scenario_part_rootfs_shrink scenario_branch_full_default scenario_branch_full_master scenario_branch_full_other scenario_branch_kernel_reject scenario_branch_rootfs_reject scenario_branch_boot_reject"

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

octal() { # hex byte -> tr octal escape
	case "$1" in
		11) printf '\021' ;;
		22) printf '\042' ;;
		33) printf '\063' ;;
		44) printf '\104' ;;
		55) printf '\125' ;;
		66) printf '\146' ;;
		a1) printf '\241' ;;
		b2) printf '\262' ;;
		c3) printf '\303' ;;
		d4) printf '\324' ;;
		e5) printf '\345' ;;
		fa) printf '\372' ;;
		*) printf '\377' ;;
	esac
}

fill_region() { # file offset_k size_k hex
	dd if=/dev/zero bs=1024 count="$3" 2>/dev/null | tr '\000' "$(octal "$4")" |
		dd of="$1" bs=1024 seek="$2" conv=notrunc 2>/dev/null
}

region_md5() { # file offset_k size_k
	dd if="$1" bs=1024 skip="$2" count="$3" 2>/dev/null | md5sum | cut -d' ' -f1
}

region_md5_bytes() { # file offset_bytes len_bytes
	local off="$2" len="$3" pre skip need
	pre=$((off % 1024))
	skip=$((off / 1024))
	need=$((pre + len))
	dd if="$1" bs=1024 skip="$skip" count=$(((need + 1023) / 1024)) 2>/dev/null |
		tail -c +$((pre + 1)) | head -c "$len" | md5sum | cut -d' ' -f1
}

pattern_md5() { # size_k hex
	dd if=/dev/zero bs=1024 count="$1" 2>/dev/null | tr '\000' "$(octal "$2")" |
		md5sum | cut -d' ' -f1
}

pattern_md5_bytes() { # len_bytes octal
	local len=$1 oct=$2 k r
	k=$((len / 1024))
	r=$((len % 1024))
	{
		if [ "$k" -gt 0 ]; then
			dd if=/dev/zero bs=1024 count="$k" 2>/dev/null | tr '\000' "$oct"
		fi
		if [ "$r" -gt 0 ]; then
			dd if=/dev/zero bs=1 count="$r" 2>/dev/null | tr '\000' "$oct"
		fi
	} | md5sum | cut -d' ' -f1
}

log_has() { # substring
	grep -qF -- "$1" "$SCRATCH/run-$NAME.log"
}

log_not_has() { # substring
	! grep -qF -- "$1" "$SCRATCH/run-$NAME.log"
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

assert_pattern_kib() { # label offset_k size_k hex
	assert_region "$1" "$2" "$3" "$(pattern_md5 "$3" "$4")"
}

assert_pattern_bytes() { # label offset_bytes len_bytes hex
	assert_region_bytes "$1" "$2" "$3" "$(pattern_md5_bytes "$3" "$(octal "$4")")"
}

assert_raw_bytes() { # label offset_bytes expected
	local got
	got=$(dd if="$FLASH" bs=1 skip="$2" count=${#3} 2>/dev/null)
	if [ "$got" = "$3" ]; then
		echo "  PASS: $1"
		PASS=$((PASS + 1))
	else
		echo "  FAIL: $1"
		FAIL=$((FAIL + 1))
	fi
}

assert_raw_not() { # label offset_bytes unexpected
	local got
	got=$(dd if="$FLASH" bs=1 skip="$2" count=${#3} 2>/dev/null)
	if [ "$got" != "$3" ]; then
		echo "  PASS: $1"
		PASS=$((PASS + 1))
	else
		echo "  FAIL: $1"
		FAIL=$((FAIL + 1))
	fi
}

assert_hex_bytes() { # label offset_bytes hex
	local got
	got=$(dd if="$FLASH" bs=1 skip="$2" count=$((${#3} / 2)) 2>/dev/null | xxd -p)
	if [ "$got" = "$3" ]; then
		echo "  PASS: $1"
		PASS=$((PASS + 1))
	else
		echo "  FAIL: $1 (got $got want $3)"
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

old_offsets() {
	OLD_BOOT_OFF=0
	OLD_ENV_OFF=$OLD_BOOT_K
	OLD_BACKUP_OFF=$((OLD_ENV_OFF + OLD_ENV_K))
	OLD_KERNEL_OFF=$((OLD_BACKUP_OFF + OLD_BACKUP_K))
	OLD_ROOTFS_OFF=$((OLD_KERNEL_OFF + OLD_KERNEL_K))
	OLD_DATA_OFF=$((OLD_ROOTFS_OFF + OLD_ROOTFS_K))
}

new_offsets() {
	NEW_BOOT_OFF=0
	NEW_ENV_OFF=$NEW_BOOT_K
	NEW_BACKUP_OFF=$((NEW_ENV_OFF + NEW_ENV_K))
	NEW_KERNEL_OFF=$((NEW_BACKUP_OFF + NEW_BACKUP_K))
	NEW_ROOTFS_OFF=$((NEW_KERNEL_OFF + NEW_KERNEL_K))
	NEW_DATA_OFF=$((NEW_ROOTFS_OFF + NEW_ROOTFS_K))
}

new_pattern_at() { # offset_k -> fill name for the new image
	if [ "$1" -lt "$NEW_ENV_OFF" ]; then
		echo a1
	elif [ "$1" -lt "$NEW_BACKUP_OFF" ]; then
		echo b2
	elif [ "$1" -lt "$NEW_KERNEL_OFF" ]; then
		echo ff
	elif [ "$1" -lt "$NEW_ROOTFS_OFF" ]; then
		echo c3
	elif [ "$1" -lt "$NEW_DATA_OFF" ]; then
		echo d4
	else
		echo e5
	fi
}

# --- flash setup -----------------------------------------------------------

setup_flash() {
	old_offsets
	echo "== setting up $FLASH (old layout)"
	dd if=/dev/zero bs=1024 count=8192 2>/dev/null | tr '\000' "$(octal ff)" >"$FLASH"
	fill_region "$FLASH" "$OLD_BOOT_OFF" "$OLD_BOOT_K" 11
	fill_region "$FLASH" "$OLD_ENV_OFF" "$OLD_ENV_K" 33
	fill_region "$FLASH" "$OLD_BACKUP_OFF" "$OLD_BACKUP_K" 22
	fill_region "$FLASH" "$OLD_KERNEL_OFF" "$OLD_KERNEL_K" 44
	fill_region "$FLASH" "$OLD_ROOTFS_OFF" "$OLD_ROOTFS_K" 55
	fill_region "$FLASH" "$OLD_DATA_OFF" "$OLD_DATA_K" 66
}

# --- VM run ----------------------------------------------------------------

run_vm() {
	local accel=()
	if [ -e /dev/kvm ]; then
		accel=(-accel kvm -cpu host)
	else
		accel=(-accel tcg)
	fi
	local cmdline="console=ttyS0 panic=-1"
	cmdline="$cmdline mtdparts=$OLD_MTDPARTS"
	cmdline="$cmdline t_mode=$MODE t_part=${PART:-} t_do_backup=${DO_BACKUP:-false}"
	cmdline="$cmdline t_boot_k=$NEW_BOOT_K t_env_k=$NEW_ENV_K t_backup_k=$NEW_BACKUP_K"
	cmdline="$cmdline t_kernel_k=$NEW_KERNEL_K t_rootfs_k=$NEW_ROOTFS_K t_data_k=$NEW_DATA_K"
	cmdline="$cmdline t_branch=${TARGET_BRANCH:-} t_upgrade=${UPGRADE_FLAG:-full} t_profile=$TEST_PROFILE"

	echo "== booting VM (scenario $NAME)"
	timeout 180 "$QEMU_BIN" -machine pc "${accel[@]}" -m 64M -smp 2 \
		-kernel "$KERNEL" -initrd "$INITRD" -append "$cmdline" \
		-drive file="$FLASH",if=none,id=fl,format=raw \
		-device virtio-blk-pci,drive=fl \
		-nographic -no-reboot >"$SCRATCH/run-$NAME.log" 2>&1
	echo "== qemu exited ($?)"
}

# --- verification ----------------------------------------------------------

assert_backup_slot() { # label offset_k backup_k
	local off_b=$(($2 * 1024)) header=64 payload=1024 rest
	assert_raw_bytes "backup magic at ${2}K" "$off_b" "THNG_BCKUP"
	assert_region_bytes "backup payload at ${2}K+64" $((off_b + header)) "$payload" \
		"$(pattern_md5_bytes "$payload" "$(octal fa)")"
	rest=$(($3 * 1024 - header - payload))
	if [ "$rest" -gt 0 ]; then
		assert_region_bytes "backup tail erased at ${2}K" $((off_b + header + payload)) "$rest" \
			"$(pattern_md5_bytes "$rest" "$(octal ff)")"
	fi
}

verify_full() {
	new_offsets
	old_offsets
	echo "== verifying $NAME (full, backup=$DO_BACKUP)"
	assert_cmd "log: stage2 started" log_has "running: sysupgrade-stage2 full"
	assert_cmd "log: offset finder" log_has "new backup offset: $((NEW_BACKUP_OFF * 1024)) (expected $((NEW_BACKUP_OFF * 1024)))"
	assert_pattern_kib "new boot at ${NEW_BOOT_OFF}K" "$NEW_BOOT_OFF" "$NEW_BOOT_K" a1
	assert_pattern_kib "new env at ${NEW_ENV_OFF}K" "$NEW_ENV_OFF" "$NEW_ENV_K" b2
	if [ "$DO_BACKUP" = "true" ]; then
		assert_backup_slot "new backup at ${NEW_BACKUP_OFF}K" "$NEW_BACKUP_OFF" "$NEW_BACKUP_K"
	else
		assert_pattern_kib "new backup slot erased at ${NEW_BACKUP_OFF}K" "$NEW_BACKUP_OFF" "$NEW_BACKUP_K" ff
	fi
	assert_hex_bytes "kernel magic at ${NEW_KERNEL_OFF}K" $((NEW_KERNEL_OFF * 1024)) 27051956
	assert_pattern_bytes "kernel body at ${NEW_KERNEL_OFF}K" $((NEW_KERNEL_OFF * 1024 + 4)) \
		$((NEW_KERNEL_K * 1024 - 4)) c3
	assert_pattern_kib "new rootfs at ${NEW_ROOTFS_OFF}K" "$NEW_ROOTFS_OFF" "$NEW_ROOTFS_K" d4
	assert_pattern_kib "new data at ${NEW_DATA_OFF}K" "$NEW_DATA_OFF" "$NEW_DATA_K" e5
	if [ "$OLD_BACKUP_OFF" -ne "$NEW_BACKUP_OFF" ]; then
		assert_raw_not "old backup slot overwritten" $((OLD_BACKUP_OFF * 1024)) "THNG_BCKUP"
		assert_pattern_kib "old backup block holds image bytes" "$OLD_BACKUP_OFF" "$OLD_BACKUP_K" \
			"$(new_pattern_at "$OLD_BACKUP_OFF")"
	fi
}

verify_part() {
	old_offsets
	echo "== verifying $NAME (part=$PART)"
	if [ "$EXPECT" = "refuse" ] || [ "$EXPECT" = "error" ]; then
		assert_cmd "flash unchanged" \
			[ "$(md5sum "$FLASH" | cut -d' ' -f1)" = "$flash_before" ]
		assert_cmd "log: error ($ERR_MSG)" log_has "$ERR_MSG"
		return
	fi
	case "$PART" in
	boot)
		assert_pattern_kib "boot image at ${OLD_BOOT_OFF}K" "$OLD_BOOT_OFF" "$NEW_BOOT_K" a1
		assert_pattern_kib "env image at ${OLD_ENV_OFF}K" "$OLD_ENV_OFF" "$NEW_ENV_K" b2
		assert_pattern_kib "backup untouched" "$OLD_BACKUP_OFF" "$OLD_BACKUP_K" 22
		assert_pattern_kib "kernel untouched" "$OLD_KERNEL_OFF" "$OLD_KERNEL_K" 44
		assert_pattern_kib "rootfs untouched" "$OLD_ROOTFS_OFF" "$OLD_ROOTFS_K" 55
		assert_pattern_kib "data untouched" "$OLD_DATA_OFF" "$OLD_DATA_K" 66
		;;
	kernel)
		assert_pattern_kib "kernel image at ${OLD_KERNEL_OFF}K" "$OLD_KERNEL_OFF" "$NEW_KERNEL_K" c3
		assert_pattern_kib "boot untouched" "$OLD_BOOT_OFF" "$OLD_BOOT_K" 11
		assert_pattern_kib "env untouched" "$OLD_ENV_OFF" "$OLD_ENV_K" 33
		assert_pattern_kib "backup untouched" "$OLD_BACKUP_OFF" "$OLD_BACKUP_K" 22
		assert_pattern_kib "rootfs untouched" "$OLD_ROOTFS_OFF" "$OLD_ROOTFS_K" 55
		assert_pattern_kib "data untouched" "$OLD_DATA_OFF" "$OLD_DATA_K" 66
		;;
	rootfs)
		assert_pattern_kib "rootfs image at ${OLD_ROOTFS_OFF}K" "$OLD_ROOTFS_OFF" "$NEW_ROOTFS_K" d4
		assert_pattern_kib "data image at ${OLD_ROOTFS_OFF}+${NEW_ROOTFS_K}K" \
			$((OLD_ROOTFS_OFF + NEW_ROOTFS_K)) "$NEW_DATA_K" e5
		local tail_k=$((OLD_ROOTFS_K + OLD_DATA_K - NEW_ROOTFS_K - NEW_DATA_K))
		if [ "$tail_k" -gt 0 ]; then
			assert_pattern_kib "data tail erased" \
				$((OLD_ROOTFS_OFF + NEW_ROOTFS_K + NEW_DATA_K)) "$tail_k" ff
		fi
		assert_pattern_kib "boot untouched" "$OLD_BOOT_OFF" "$OLD_BOOT_K" 11
		assert_pattern_kib "env untouched" "$OLD_ENV_OFF" "$OLD_ENV_K" 33
		assert_pattern_kib "backup untouched" "$OLD_BACKUP_OFF" "$OLD_BACKUP_K" 22
		assert_pattern_kib "kernel untouched" "$OLD_KERNEL_OFF" "$OLD_KERNEL_K" 44
		;;
	esac
}

verify_branch() {
	echo "== verifying $NAME (branch=${TARGET_BRANCH:-default}, upgrade=$UPGRADE_FLAG)"
	assert_cmd "flash unchanged" \
		[ "$(md5sum "$FLASH" | cut -d' ' -f1)" = "$flash_before" ]
	if [ "$EXPECT" = "refuse" ]; then
		assert_cmd "log: error ($ERR_MSG)" log_has "$ERR_MSG"
		assert_cmd "log: no download attempted" log_not_has "CURL-REQ"
		return
	fi
	assert_cmd "log: requested $EXPECT_URL" log_has "$EXPECT_URL"
}

verify() {
	case "$MODE" in
		full) verify_full ;;
		part) verify_part ;;
		branch) verify_branch ;;
	esac
}

# --- main ------------------------------------------------------------------

run_scenario() {
	# reset per-scenario defaults
	NAME=
	MODE=full
	PART=
	OLD_BOOT_K=192
	NEW_BOOT_K=192
	OLD_ENV_K=64
	OLD_BACKUP_K=64
	OLD_KERNEL_K=1600
	OLD_ROOTFS_K=5120
	NEW_ENV_K=64
	NEW_BACKUP_K=64
	NEW_KERNEL_K=1600
	NEW_ROOTFS_K=5120
	DO_BACKUP=true
	EXPECT=flash
	ERR_MSG=
	TARGET_BRANCH=
	UPGRADE_FLAG=full
	EXPECT_URL=
	"$1"

	OLD_DATA_K=$((8192 - (OLD_BOOT_K + OLD_ENV_K + OLD_BACKUP_K + OLD_KERNEL_K + OLD_ROOTFS_K)))
	NEW_DATA_K=$((8192 - (NEW_BOOT_K + NEW_ENV_K + NEW_BACKUP_K + NEW_KERNEL_K + NEW_ROOTFS_K)))
	OLD_MTDPARTS="block2mtd:${OLD_BOOT_K}k(boot),${OLD_ENV_K}k(env),${OLD_BACKUP_K}k(backup),${OLD_KERNEL_K}k(kernel),${OLD_ROOTFS_K}k(rootfs),${OLD_DATA_K}k(data),8192k@0(all)"

	if [ "$OLD_DATA_K" -le 0 ] || [ "$NEW_DATA_K" -le 0 ]; then
		echo "ERROR: scenario $NAME has an invalid data size" >&2
		exit 1
	fi

	echo
	echo "============================================================"
	echo "SCENARIO: $NAME"
	echo "  old layout: $OLD_MTDPARTS"
	echo "  new: boot=${NEW_BOOT_K}K rootfs=${NEW_ROOTFS_K}K data=${NEW_DATA_K}K mode=$MODE part=${PART:-} expect=$EXPECT"
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
