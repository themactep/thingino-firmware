#!/bin/sh
# shellcheck shell=bash
# shellcheck disable=SC2155
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
# The thingino branch is maintained by merging upstream u-boot into itself, so
# a single base..branch diff carries upstream churn plus the thingino work.
# The patch is split at the most recent upstream merge so the thingino patch
# stays small and reviewable:
#   0001-from-<version>-to-u-boot-head.patch   upstream churn
#   0002-from-u-boot-head-to-thingino.patch    thingino changes
# When the branch has no merge in its first-parent history (it was rebased),
# the split point falls back to the upstream merge the rebase sits on, which
# the same detection finds. If neither exists, the script falls back to a
# single 0001-from-<version>-to-thingino.patch.
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
#   <firmware-repo>/package/all-patches/uboot/<version>/0001-from-<version>-to-u-boot-head.patch
#   <firmware-repo>/package/all-patches/uboot/<version>/0002-from-u-boot-head-to-thingino.patch

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FIRMWARE_DEFAULT="$(cd "$SCRIPT_DIR/.." && pwd)"

REMOTE_URL="https://github.com/themactep/u-boot"

# History window fetched for the thingino branch. Must reach back past the
# most recent upstream merge; the branch accumulates thingino commits between
# merges, so keep a generous window without pulling the whole u-boot history.
BRANCH_FETCH_DEPTH=4000

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
SINGLE_PATCH_FILE="$PATCH_DIR/0001-from-${VERSION}-to-thingino.patch"
UPSTREAM_PATCH_FILE="$PATCH_DIR/0001-from-${VERSION}-to-u-boot-head.patch"
THINGINO_PATCH_FILE="$PATCH_DIR/0002-from-u-boot-head-to-thingino.patch"
WORK_DIR="$FIRMWARE_REPO/overrides/u-boot"

echo "target:       ${TARGET:-<inferred>}"
echo "remote:       $REMOTE_URL"
echo "base ref:     $BASE"
echo "branch:       $BRANCH"
echo "version:      $VERSION"
echo "patch dir:    $PATCH_DIR"
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
	git -C "$WORK_DIR" fetch origin "refs/heads/$BRANCH:refs/heads/$BRANCH" --depth="$BRANCH_FETCH_DEPTH" --no-tags --quiet
else
	echo "==> (dry run) would fetch $BASE and $BRANCH into $WORK_DIR"
fi

# --- find the upstream split point ---
# The most recent merge in the branch's first-parent history is the last
# upstream merge the thingino work sits on top of. For a rebased branch the
# same walk lands on the upstream merge the rebase sits on. If neither is
# reachable within the fetch window, fall back to a single combined patch.
SPLIT_HEAD="$(git -C "$WORK_DIR" log --first-parent --merges -1 --format=%H "$BRANCH" 2>/dev/null || true)"

mkdir -p "$PATCH_DIR"

if [ -n "$SPLIT_HEAD" ] && [ "$SPLIT_HEAD" != "$BASE" ]; then
	echo "==> Split point: $SPLIT_HEAD"
	echo "==> Generating diff $BASE..$SPLIT_HEAD (upstream churn)..."

	if [ "$DRY_RUN" = false ]; then
		git -C "$WORK_DIR" diff "$BASE".."$SPLIT_HEAD" >"$UPSTREAM_PATCH_FILE"
		git -C "$WORK_DIR" diff "$SPLIT_HEAD".."$BRANCH" >"$THINGINO_PATCH_FILE"
		rm -f "$SINGLE_PATCH_FILE"

		L1=$(wc -l <"$UPSTREAM_PATCH_FILE")
		S1=$(du -h "$UPSTREAM_PATCH_FILE" | cut -f1)
		L2=$(wc -l <"$THINGINO_PATCH_FILE")
		S2=$(du -h "$THINGINO_PATCH_FILE" | cut -f1)
		echo "==> Patch written: $UPSTREAM_PATCH_FILE ($L1 lines, $S1)"
		echo "==> Patch written: $THINGINO_PATCH_FILE ($L2 lines, $S2)"
	else
		echo "    (dry run) git diff $BASE..$SPLIT_HEAD > $UPSTREAM_PATCH_FILE"
		echo "    (dry run) git diff $SPLIT_HEAD..$BRANCH > $THINGINO_PATCH_FILE"
	fi
else
	echo "==> Generating diff $BASE..$BRANCH..."

	if [ "$DRY_RUN" = false ]; then
		git -C "$WORK_DIR" diff "$BASE".."$BRANCH" >"$SINGLE_PATCH_FILE"
		rm -f "$UPSTREAM_PATCH_FILE" "$THINGINO_PATCH_FILE"

		LINES=$(wc -l <"$SINGLE_PATCH_FILE")
		SIZE=$(du -h "$SINGLE_PATCH_FILE" | cut -f1)
		echo "==> Patch written: $SINGLE_PATCH_FILE ($LINES lines, $SIZE)"
	else
		echo "    (dry run) git diff $BASE..$BRANCH > $SINGLE_PATCH_FILE"
	fi
fi
