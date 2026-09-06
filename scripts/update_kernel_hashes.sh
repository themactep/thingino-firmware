#!/bin/sh
#
# Report or bump the pinned kernel commits in thingino.mk.
#
# Custom-git kernels (everything except 3.10.14, which uses the official
# kernel.org tarball) are pinned to specific commits in thingino.mk so
# builds are reproducible and make does not hit the network at parse
# time. When a branch advances, its pin goes stale; this script reports
# the drift and, with --apply, bumps stale pins to the current tips.
#
# The hashes are read from git ls-remote's refs/heads output, so a value
# is the branch tip commit by construction and is never typed by hand.
#
# Usage:
#   scripts/update_kernel_hashes.sh           report drift (exit 1 if stale)
#   scripts/update_kernel_hashes.sh --apply   bump stale pins in place
#

set -eu

KERNEL_REPO="https://github.com/gtxaspec/thingino-linux"
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
MK_FILE=$(cd "$SCRIPT_DIR/.." && pwd)/thingino.mk

apply=0
case "${1:-}" in
	--apply) apply=1 ;;
	--help | -h)
		cat >&2 <<'EOF'
Usage: scripts/update_kernel_hashes.sh [--apply]

Report the kernel commit pins in thingino.mk against the remote
(github.com/gtxaspec/thingino-linux). With --apply, bump stale pins to
the current branch tips in place.
EOF
		exit 0
		;;
	"") : ;;
	*)
		echo "Unknown argument: $1" >&2
		exit 2
		;;
esac

map_file=$(mktemp)
trap 'rm -f "$map_file"' EXIT

# Pull the branch -> hash pairs out of the KERNEL_HASH map.
awk '
	/KERNEL_BRANCH\),ingenic-/ {
		b = $0
		sub(/.*ingenic-/, "ingenic-", b)
		sub(/\)$/, "", b)
		next
	}
	/KERNEL_HASH := [0-9a-f]{40}/ && b != "" {
		hash = $0
		sub(/.*KERNEL_HASH := /, "", hash)
		print b " " hash
		b = ""
	}
' "$MK_FILE" >"$map_file"

if [ ! -s "$map_file" ]; then
	echo "No pinned kernel branches found in $MK_FILE" >&2
	exit 1
fi

remote_heads=$(git ls-remote "$KERNEL_REPO" 2>/dev/null) || {
	echo "Failed to list $KERNEL_REPO" >&2
	exit 1
}

stale=0
missing=0
while IFS= read -r entry; do
	branch=${entry%% *}
	pinned=${entry#* }

	remote=$(printf '%s\n' "$remote_heads" |
		awk -v ref="refs/heads/$branch" '$2 == ref { print $1 }')

	if [ -z "$remote" ]; then
		printf 'missing  %s (branch does not exist on remote)\n' "$branch"
		missing=1
		continue
	fi

	if [ "$pinned" = "$remote" ]; then
		printf 'current  %s  %s\n' "$branch" "$pinned"
	else
		printf 'stale    %s  %s -> %s\n' "$branch" "$pinned" "$remote"
		stale=1
		if [ "$apply" = 1 ]; then
			sed -i "s|$pinned|$remote|" "$MK_FILE"
		fi
	fi
done <"$map_file"

if [ "$apply" = 1 ]; then
	if [ "$stale" = 1 ]; then
		echo "Updated $MK_FILE"
	fi
	exit "$missing"
fi

if [ "$stale" = 1 ] || [ "$missing" = 1 ]; then
	exit 1
fi
