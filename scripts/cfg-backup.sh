#!/bin/sh
# shellcheck shell=bash
# cfg-backup - read/write config tarball to the raw 64KB backup MTD partition
#
# Usage:
#   cfg-backup write [paths...]    (defaults to /etc/cfg-backup.list)
#   cfg-backup restore
#
# Header (64 bytes, text):
#   THNG_BCKUP\n
#   size=<decimal>\n
#   md5=<32 hex>\n
#   (padded with \n)
#
# Payload: tar (uncompressed - busybox tar lacks gzip)

set -e

MTD=${CFG_BACKUP_MTD:-}
HEADER_SIZE=64
MAX_PAYLOAD=$((65536 - HEADER_SIZE))
LIST_FILE=/etc/cfg-backup.list

die() {
	echo "cfg-backup: $*" >&2
	exit 1
}

# Resolve the backup MTD partition by name - partition numbers are not
# stable across flash layouts (NOR vs NAND). $CFG_BACKUP_MTD overrides.
if [ -z "$MTD" ]; then
	MTD="/dev/$(awk -F: '/"backup"$/{print $1}' /proc/mtd)"
fi
[ -e "$MTD" ] || die "backup MTD partition not found ($MTD)"

# Try to erase the MTD partition. Uses flash_eraseall (whole partition)
# or flash_erase (count blocks to cover the partition size).
do_erase() {
	if command -v flash_eraseall >/dev/null 2>&1; then
		flash_eraseall "$MTD" 2>/dev/null || true
	elif command -v flash_erase >/dev/null 2>&1; then
		# Erase enough blocks to cover the full partition
		local eb_sz count
		eb_sz=$(awk "/^$(basename "$MTD"):/{print \$3}" /proc/mtd)
		eb_sz=$((0x$eb_sz))
		count=$((65536 / eb_sz))
		flash_erase "$MTD" 0 "$count" 2>/dev/null || true
	fi
}

do_write() {
	if [ $# -eq 0 ]; then
		[ -f "$LIST_FILE" ] || die "no paths given and $LIST_FILE not found"
		# Read paths from list file, skipping comments and blank lines.
		# Always include the list file itself first.
		set -- "$LIST_FILE"
		while IFS= read -r line; do
			line=$(echo "$line" | sed 's/#.*//; s/^[[:space:]]*//; s/[[:space:]]*$//')
			[ -n "$line" ] && set -- "$@" "$line"
		done <"$LIST_FILE"
	else
		# CLI paths given - still prepend the list file so backups are
		# self-describing.
		set -- "$LIST_FILE" "$@"
	fi

	# Drop paths that do not exist so tar does not abort midway
	# (the default list may name files a given camera does not have).
	_count=$#
	_i=0
	while [ "$_i" -lt "$_count" ]; do
		_p=$1
		shift
		if [ -e "$_p" ]; then
			set -- "$@" "$_p"
		else
			echo "cfg-backup: skipping missing path: $_p" >&2
		fi
		_i=$((_i + 1))
	done
	[ $# -gt 0 ] || die "nothing to back up"

	tmpd=$(mktemp -d)
	trap 'rm -rf "$tmpd"' EXIT

	tar cf "$tmpd/payload" "$@" 2>/dev/null || die "tar failed"

	sz=$(stat -c%s "$tmpd/payload" 2>/dev/null) || sz=$(wc -c <"$tmpd/payload")
	[ "$sz" -le "$MAX_PAYLOAD" ] ||
		die "backup too large: $sz bytes (max $MAX_PAYLOAD)"

	md5=$(md5sum "$tmpd/payload" | awk '{print $1}')

	# Build 64-byte text header
	# Build header, then pad to exactly HEADER_SIZE bytes
	printf 'THNG_BCKUP\nsize=%d\nmd5=%s\n' "$sz" "$md5" >"$tmpd/header"
	local actual pad
	actual=$(stat -c%s "$tmpd/header" 2>/dev/null) || actual=$(wc -c <"$tmpd/header")
	pad=$((HEADER_SIZE - actual))
	[ "$pad" -gt 0 ] && dd if=/dev/zero bs=1 count=$pad 2>/dev/null | tr '\0' '\n' >>"$tmpd/header"

	# Build combined header+payload file for flashcp
	cat "$tmpd/header" "$tmpd/payload" >"$tmpd/combined"

	do_erase
	flashcp -v "$tmpd/combined" "$MTD" 2>/dev/null

	echo "cfg-backup: $sz bytes written to $MTD"
}

do_restore() {
	tmpd=$(mktemp -d)
	trap 'rm -rf "$tmpd"' EXIT

	dd if="$MTD" of="$tmpd/full" bs=65536 count=1 2>/dev/null

	# Check magic
	magic=$(dd if="$tmpd/full" bs=10 count=1 2>/dev/null | tr -d '\n\0')
	[ "$magic" = "THNG_BCKUP" ] || die "no valid backup found on $MTD"

	header=$(dd if="$tmpd/full" bs="$HEADER_SIZE" count=1 2>/dev/null)
	sz=$(echo "$header" | grep '^size=' | sed 's/^size=//')
	stored_md5=$(echo "$header" | grep '^md5=' | sed 's/^md5=//')

	if [ -z "$sz" ] || [ -z "$stored_md5" ]; then
		die "corrupt backup header"
	fi
	[ "$sz" -le "$MAX_PAYLOAD" ] || die "stored size $sz exceeds max $MAX_PAYLOAD"

	dd if="$tmpd/full" of="$tmpd/payload" bs=1 skip="$HEADER_SIZE" count="$sz" 2>/dev/null
	computed_md5=$(md5sum "$tmpd/payload" | awk '{print $1}')

	[ "$stored_md5" = "$computed_md5" ] || die "MD5 mismatch - backup is corrupt"

	tar xf "$tmpd/payload" -C / || die "tar extract failed"
	echo "cfg-backup: $sz bytes restored from $MTD"
}

case "${1:-}" in
	write)
		shift
		do_write "$@"
		;;
	restore) do_restore ;;
	*)
		echo "Usage: $0 write <paths...>" >&2
		echo "       $0 restore" >&2
		exit 1
		;;
esac
