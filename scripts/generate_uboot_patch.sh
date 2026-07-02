#!/bin/sh
#
# generate_uboot_patch.sh — regenerate u-boot thingino patches
#
# Maintains a shallow clone of https://github.com/themactep/u-boot in
# overrides/u-boot/ (repurposable for local development via local.mk) and
# diffs the baseline branch against the thingino branch.
#
# Two u-boot trees are supported:
#   xburst2 (T40/T41/A1): base=202604, branch=ingenic-t-series
#   xburst1 (T10-T31):    base=201307, branch=ingenic-xburst1
#
# Usage:
#   ./scripts/generate_uboot_patch.sh [OPTIONS]
#
# Options:
#   -t, --target {xburst1,xburst2}  which u-boot tree (default: auto-detect from -b)
#   -f, --firmware-repo DIR         path to thingino-firmware (default: repo root)
#   -b, --base REF                  base branch (default: 202604)
#   -B, --branch BRANCH             thingino branch (default: per-target)
#   -n, --dry-run                   show what would happen without doing it
#   -h, --help                      show this help
#
# Output:
#   <firmware-repo>/package/all-patches/uboot/<version>/0001-from-<version>-to-thingino.patch

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FIRMWARE_DEFAULT="$(cd "$SCRIPT_DIR/.." && pwd)"

REMOTE_URL="https://github.com/themactep/u-boot"

# --- defaults ---
TARGET=""
FIRMWARE_REPO="$FIRMWARE_DEFAULT"
BASE=""
BRANCH=""
DRY_RUN=false

usage() {
	sed -n '/^# Usage:/,/^$/p' "$0" | sed 's/^# \?//'
	exit 0
}

while [ $# -gt 0 ]; do
	case "$1" in
		-t | --target)
			TARGET="$2"
			shift 2
			;;
		-f | --firmware-repo)
			FIRMWARE_REPO="$2"
			shift 2
			;;
		-b | --base)
			BASE="$2"
			shift 2
			;;
		-B | --branch)
			BRANCH="$2"
			shift 2
			;;
		-n | --dry-run)
			DRY_RUN=true
			shift
			;;
		-h | --help) usage ;;
		*)
			echo "unknown option: $1" >&2
			exit 1
			;;
	esac
done

# --- apply target defaults ---
apply_defaults() {
	if [ -n "$TARGET" ]; then
		case "$TARGET" in
			xburst2)
				BASE="${BASE:-202604}"
				BRANCH="${BRANCH:-ingenic-t-series}"
				;;
			xburst1)
				BASE="${BASE:-201307}"
				BRANCH="${BRANCH:-ingenic-xburst1}"
				;;
			*)
				echo "error: unknown target '$TARGET' (use xburst1 or xburst2)" >&2
				exit 1
				;;
		esac
	else
		if [ -z "$BASE" ]; then
			BASE="202604"
		fi
		case "$BASE" in
			20[0-9][0-9][0-9][0-9])
				BRANCH="${BRANCH:-ingenic-t-series}"
				;;
			201307)
				BRANCH="${BRANCH:-ingenic-xburst1}"
				;;
			*)
				echo "error: cannot infer target from base '$BASE'. Use -t to specify." >&2
				exit 1
				;;
		esac
	fi
}

apply_defaults

# --- derive version string from base ref ---
version_from_ref() {
	local ref="$1"
	case "$ref" in
		20[0-9][0-9][0-9][0-9])
			local y="${ref%"$(echo "$ref" | cut -c5-)"}"
			local m="$(echo "$ref" | cut -c5-6)"
			echo "${y}.${m}"
			;;
		*)
			echo "$ref"
			;;
	esac
}

VERSION="$(version_from_ref "$BASE")"
PATCH_DIR="$FIRMWARE_REPO/package/all-patches/uboot/$VERSION"
PATCH_FILE="$PATCH_DIR/0001-from-${VERSION}-to-thingino.patch"
WORK_DIR="$FIRMWARE_REPO/overrides/u-boot"

echo "target:       ${TARGET:-<inferred>}"
echo "remote:       $REMOTE_URL"
echo "base ref:     $BASE"
echo "branch:       $BRANCH"
echo "version:      $VERSION"
echo "patch path:   $PATCH_FILE"
echo "work dir:     $WORK_DIR"
echo

# --- preflight ---
command -v git >/dev/null 2>&1 || {
	echo "error: git not found" >&2
	exit 1
}
[ -d "$FIRMWARE_REPO/package" ] || {
	echo "error: $FIRMWARE_REPO does not look like thingino-firmware" >&2
	exit 1
}

# --- set up / update shallow clone ---
if [ "$DRY_RUN" = false ]; then
	if [ ! -d "$WORK_DIR/.git" ]; then
		echo "==> Creating clone at $WORK_DIR..."
		mkdir -p "$WORK_DIR"
		git -C "$WORK_DIR" init -q
		git -C "$WORK_DIR" remote add origin "$REMOTE_URL"
	fi

	echo "==> Fetching base branch $BASE..."
	git -C "$WORK_DIR" fetch origin "refs/heads/$BASE:refs/heads/$BASE" --depth=1 --no-tags --quiet
	echo "==> Fetching thingino branch $BRANCH..."
	git -C "$WORK_DIR" fetch origin "refs/heads/$BRANCH:refs/heads/$BRANCH" --depth=1 --no-tags --quiet
else
	echo "==> (dry run) would fetch $BASE and $BRANCH into $WORK_DIR"
fi

# --- generate patch ---
echo "==> Generating diff $BASE..$BRANCH..."
mkdir -p "$PATCH_DIR"

if [ "$DRY_RUN" = false ]; then
	git -C "$WORK_DIR" diff "$BASE".."$BRANCH" >"$PATCH_FILE"
	LINES=$(wc -l <"$PATCH_FILE")
	SIZE=$(du -h "$PATCH_FILE" | cut -f1)
	echo "==> Patch written: $PATCH_FILE ($LINES lines, $SIZE)"
else
	echo "    (dry run) git diff $BASE..$BRANCH > $PATCH_FILE"
fi
