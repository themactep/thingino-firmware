#!/bin/sh

# Move Buildroot download-cache files between the local cache (BR2_DL_DIR) and
# the shared mirror (DL_MIRROR_DIR). Never deletes anything on either side.
#
#   pull  - bulk copy from the mirror into the local cache (pre-warm only)
#   push  - copy local files the mirror does not have yet
#   check - print the mirror filesystem type; fail unless it is a network fs
#
# Only a network-hosted directory is a mirror. A local directory is used
# directly, so DL_MIRROR_DIR should point at BR2_DL_DIR in that case.

set -eu

usage() {
	echo "usage: $0 pull|push|check" >&2
	exit 1
}

[ $# -eq 1 ] || usage

: "${BR2_DL_DIR:?BR2_DL_DIR is not set}"
: "${DL_MIRROR_DIR:?DL_MIRROR_DIR is not set}"

manifest="$BR2_DL_DIR/.mirror-manifest"
lock="$BR2_DL_DIR/.mirror-lock"

mirror_fstype() {
	stat -f -c %T "$DL_MIRROR_DIR" 2>/dev/null || true
}

is_network_fs() {
	case "$1" in
		nfs* | cifs* | smb* | sshfs | fuse.sshfs | fuse.rclone | 9p | davfs* | fuse.davfs*) return 0 ;;
		*) return 1 ;;
	esac
}

do_check() {
	[ -d "$DL_MIRROR_DIR" ] || {
		echo none
		return 1
	}
	fs="$(mirror_fstype)"
	echo "${fs:-none}"
	is_network_fs "$fs"
}

# A local directory is meant to be used as BR2_DL_DIR directly: nothing to
# mirror, and no reason to fail a build over it.
require_network_mirror() {
	fs="$(mirror_fstype)"
	if ! is_network_fs "$fs"; then
		echo "Mirror $DL_MIRROR_DIR is ${fs:-unavailable}, not a network filesystem; set BR2_DL_DIR to it directly instead" >&2
		exit 0
	fi
}

# Relative names of local cache files that are actual sources. Lock, manifest,
# update stamps and cache archives are internal bookkeeping.
list_local() {
	find "$BR2_DL_DIR" -type f \
		! -name '.mirror-*' \
		! -name '*.github-updated-at' \
		! -name '*.zip*' \
		-printf '%P\n' | LC_ALL=C sort
}

require_dirs() {
	[ -d "$BR2_DL_DIR" ] || {
		echo "ERROR: local cache $BR2_DL_DIR does not exist" >&2
		exit 1
	}
	[ -d "$DL_MIRROR_DIR" ] || {
		echo "ERROR: mirror $DL_MIRROR_DIR is not accessible" >&2
		exit 1
	}
}

do_pull() {
	require_dirs
	require_network_mirror
	echo "Pulling $DL_MIRROR_DIR -> $BR2_DL_DIR"
	rsync -a --ignore-existing "$DL_MIRROR_DIR/" "$BR2_DL_DIR/"
}

do_push() {
	require_dirs
	require_network_mirror

	exec 9>"$lock"
	flock -x 9

	names="$(mktemp)"
	new="$(mktemp)"
	sorted="$(mktemp)"
	trap 'rm -f "$names" "$new" "$sorted"' EXIT

	list_local >"$names"
	if [ ! -f "$manifest" ]; then : >"$manifest"; fi
	LC_ALL=C comm -23 "$names" "$manifest" >"$new"

	if [ ! -s "$new" ]; then
		echo "Mirror is up to date"
		return 0
	fi

	rsync -a --ignore-existing --files-from="$new" "$BR2_DL_DIR/" "$DL_MIRROR_DIR/"

	# Keep the manifest sorted and unique: comm needs a sorted input, and the
	# new names are not necessarily greater than every recorded one.
	LC_ALL=C sort -u "$manifest" "$new" >"$sorted"
	mv "$sorted" "$manifest"

	echo "Pushed $(wc -l <"$new") file(s) to $DL_MIRROR_DIR"
}

case "$1" in
	pull) do_pull ;;
	push) do_push ;;
	check) do_check ;;
	*) usage ;;
esac
