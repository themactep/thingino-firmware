#!/bin/bash
# shellcheck disable=SC2086,SC2029,SC2001
# SC2086: $SSH_OPTS is a space-separated option list that must word-split.
# SC2029: remote commands intentionally expand local variables client-side.
# SC2001: trim() via sed is clearer than nested ${var//} expansions here.
#
# user-push - apply user preference files to already-flashed cameras
# without rebuilding firmware.
#
# Each camera is matched against the user config layers and everything
# applicable is pushed over SSH:
#   user/common/overlay/*        -> same paths on the camera
#   user/<camera>/overlay/*      -> same paths on the camera
#   user/<camera>/<ip>/overlay/* -> same paths on the camera
#   user/*/opt/*                 -> /opt on the camera
#   user/*/thingino.json         -> jct import into /etc/thingino.json
#   user/*/prudynt.json          -> jct import into /etc/prudynt.json
#
# Build-time-only inputs (local.fragment, local.mk, local.uenv.txt) are
# skipped: they are baked into the firmware image at compile time.
#
# The camera's defconfig name is read from IMAGE_ID in /etc/os-release
# and selects the per-camera layer. Layer precedence (later wins) is the
# same as in the build: common < camera < device.
#
# The camera model is always detected by querying IMAGE_ID from the
# device itself, so a fleet update needs nothing but a list of IPs.
# The model just selects the per-camera layer under user/<camera>.
#
# Usage:
#   user-push.sh -i <ip>                 single camera
#   user-push.sh -r <roster>             fleet from a file: one IP per line
#   user-push.sh <ip> [ip ...]           fleet from command line
#   user-push.sh 192.168.1.10-192.168.1.20   fleet from an address range
#
# IPs and roster lines may be a single address or a from-to range
# (start-end); ranges are expanded before matching.
#
# Options:
#   -n             dry run: print the plan, change nothing
#   -S             skip the pre-change /overlay backup
#   -R             reboot the camera after applying changes
#   -b <dir>       backup directory (default: $HOME/.thingino/backups)
#   -v             verbose: print every applied file
#   -h             this help
#
# Before anything changes, a full backup of the camera's /overlay is
# saved to <backup_dir>/<ip>-<camera>-<timestamp>.tar.gz by calling
# scripts/backup_overlay.sh. Restore with: tar -xzf <file> -C /

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
USER_DIR="${THINGINO_USER_DIR:-$ROOT_DIR/user}"
BACKUP_DIR="${THINGINO_BACKUP_DIR:-$HOME/.thingino/backups}"

SSH_OPTS="-T -o ConnectTimeout=10 -o ServerAliveInterval=5 -o ServerAliveCountMax=6 \
-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"

DRY_RUN=0
DO_BACKUP=1
DO_REBOOT=0
VERBOSE=0
IPS=()
ROSTER=""

die() { echo -e "\e[38;5;160mERROR: $*\e[0m" >&2; exit 1; }
warn() { echo -e "\e[38;5;214mWARN: $*\e[0m" >&2; }
log() { echo -e "$*"; }

usage() {
	sed -n '/^# user-push -/,/^[^#]/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'
	exit "${1:-0}"
}

while getopts "i:r:b:nSRvh" opt; do
	case "$opt" in
		i) IPS+=("$OPTARG") ;;
		r) ROSTER="$OPTARG" ;;
		b) BACKUP_DIR="$OPTARG" ;;
		n) DRY_RUN=1 ;;
		S) DO_BACKUP=0 ;;
		R) DO_REBOOT=1 ;;
		v) VERBOSE=1 ;;
		h) usage 0 ;;
		*) usage 1 ;;
	esac
done
shift $((OPTIND - 1))
IPS+=("$@")

[ -d "$USER_DIR" ] || die "user directory not found: $USER_DIR (set THINGINO_USER_DIR)"

rsh() { ssh $SSH_OPTS "$REMOTE_HOST" "$@"; }
# Same but with stdin closed: required inside the roster read loop, where
# the roster file is the loop's stdin and ssh would otherwise drain it.
rshn() { ssh $SSH_OPTS "$REMOTE_HOST" "$@" < /dev/null; }

# Read IMAGE_ID from the device and normalize it to a defconfig name.
detect_camera() {
	local out
	out=$(rshn "grep '^IMAGE_ID=' /etc/os-release 2>/dev/null || grep '^IMAGE_ID=' /usr/lib/os-release 2>/dev/null" 2>/dev/null) || return 1
	[ -n "$out" ] || return 1
	out=$(printf '%s' "$out" | cut -d'=' -f2 | tr -d '\n\r' | xargs)
	out="${out%-3.10}"
	out="${out%-4.4}"
	[ -n "$out" ] && printf '%s\n' "$out"
}

ip2int() { local IFS=. a b c d; read -r a b c d <<<"$1"; echo $((a << 24 | b << 16 | c << 8 | d)); }
int2ip() { local n=$1; echo "$((n >> 24 & 255)).$((n >> 16 & 255)).$((n >> 8 & 255)).$((n & 255))"; }

# Print one IP per line for an address or a from-to range (start-end).
expand_ip() {
	local arg="$1" start end s e t
	if [[ "$arg" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}-([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
		start="${arg%-*}"
		end="${arg#*-}"
		s=$(ip2int "$start")
		e=$(ip2int "$end")
		if [ "$s" -gt "$e" ]; then
			warn "range reversed, swapping: $arg"
			t=$s; s=$e; e=$t
		fi
		if [ $((e - s)) -ge 65536 ]; then
			warn "range too large, capping at 65536 addresses: $arg"
			e=$((s + 65535))
		fi
		for ((i = s; i <= e; i++)); do
			int2ip "$i"
		done
	else
		echo "$arg"
	fi
}

# Layers in precedence order (later wins): common, camera, device.
collect_layers() {
	local camera="$1" ip="$2"
	[ -d "$USER_DIR/common" ] && echo "$USER_DIR/common"
	if [ -n "$camera" ] && [ -d "$USER_DIR/$camera" ]; then
		echo "$USER_DIR/$camera"
		if [ -n "$ip" ] && [ -d "$USER_DIR/$camera/$ip" ]; then
			echo "$USER_DIR/$camera/$ip"
		fi
	fi
}

find_host_jct() {
	[ -n "${JCT:-}" ] && [ -x "$JCT" ] && { echo "$JCT"; return 0; }
	command -v jct 2>/dev/null && return 0
	# Output trees can live in the repo or in THINGINO_OUTPUT_ROOT_DIR
	# (the Makefile honors both).
	find "$ROOT_DIR/output" "${THINGINO_OUTPUT_ROOT_DIR:-$ROOT_DIR/output}" \
		-path '*/host/bin/jct' -type f -perm -u+x 2>/dev/null | head -1
}

layer_file_count() {
	local layer="$1" subdir="$2"
	[ -d "$layer/$subdir" ] || { echo 0; return; }
	find "$layer/$subdir" -mindepth 1 ! -name '.*keep' ! -name '.empty' 2>/dev/null | wc -l
}

# Stream a layer subtree onto the device (tar preserves modes and symlinks).
apply_overlay_layer() {
	local layer="$1" subdir="$2" dest="$3"
	local src="$layer/$subdir" count
	count=$(layer_file_count "$layer" "$subdir")
	[ "$count" -gt 0 ] || return 0
	if [ "$count" -eq 1 ]; then
		log "  overlay: $src (1 entry) -> ${dest%/}/"
	else
		log "  overlay: $src ($count entries) -> ${dest%/}/"
	fi
	if [ "$VERBOSE" -eq 1 ]; then
		find "$src" \( -type f -o -type l \) | sed "s|^$src/|    |" | sort
	fi
	if [ "$DRY_RUN" -eq 0 ]; then
		# Stub files (.*keep, .empty) are stripped by the build too.
		# --owner/--group: archive as root so the camera's busybox tar
		# restores root ownership, matching mkfs.jffs2 --squash in the
		# build (dropbear refuses keys from non-root-owned files).
		if ! tar --exclude='.*keep' --exclude='.empty' --owner=0 --group=0 -cf - -C "$src" . | rsh "tar -xf - -C $dest"; then
			warn "failed to apply $src to $REMOTE_HOST"
			return 1
		fi
	fi
}

# Merge a JSON partial into a config file on the device with jct.
# Prefers the device's own jct; falls back to a host jct if the device
# lacks one (pull, merge locally, push back).
import_json() {
	local target="$1" partial="$2"
	local remote_tmp jct_host tmpfile
	log "  json: import $partial -> $target"
	if [ "$DRY_RUN" -eq 1 ]; then
		return 0
	fi
	# scp -O only: dropbear does not propagate stdin EOF, so piping a
	# file into 'cat >' over ssh hangs the remote cat forever.
	if rshn "command -v jct >/dev/null 2>&1"; then
		remote_tmp="/tmp/up-$(basename "$target")"
		if ! scp -O -q $SSH_OPTS "$partial" "$REMOTE_HOST:$remote_tmp"; then
			warn "failed to upload $partial to $REMOTE_HOST"
			return 1
		fi
		if ! rshn "jct $target import $remote_tmp && rm -f $remote_tmp"; then
			warn "jct import failed on $REMOTE_HOST for $target"
			return 1
		fi
	else
		jct_host=$(find_host_jct) || {
			warn "no jct on device or host; cannot import $partial into $target"
			return 1
		}
		tmpfile=$(mktemp "${TMPDIR:-/tmp}/userpush.XXXXXX")
		if scp -O -q $SSH_OPTS "$REMOTE_HOST:$target" "$tmpfile" 2>/dev/null && [ -s "$tmpfile" ]; then
			"$jct_host" "$tmpfile" import "$partial"
		else
			cp "$partial" "$tmpfile"
		fi
		if ! scp -O -q $SSH_OPTS "$tmpfile" "$REMOTE_HOST:$target"; then
			rm -f "$tmpfile"
			warn "failed to push merged $target to $REMOTE_HOST"
			return 1
		fi
		rm -f "$tmpfile"
	fi
}

restart_prudynt() {
	if rshn "pidof prudynt >/dev/null 2>&1 && /etc/init.d/S31prudynt restart >/dev/null 2>&1"; then
		log "  prudynt restarted (prudynt.json changed)"
	fi
}

apply_camera() {
	local ip="$1"
	local camera layers layer status=0
	REMOTE_HOST="root@$ip"

	log ""
	log "===== $ip ====="

	camera=$(detect_camera) || {
		warn "cannot reach or identify camera at $ip"
		return 1
	}
	log "  camera: $camera"

	mapfile -t layers < <(collect_layers "$camera" "$ip")
	[ "${#layers[@]}" -gt 0 ] || {
		log "  no user files apply to this camera"
		return 0
	}
	log "  layers:"
	for layer in "${layers[@]}"; do
		log "   - $layer"
	done

	# Full backup of the camera's /overlay before anything changes.
	if [ "$DRY_RUN" -eq 0 ] && [ "$DO_BACKUP" -eq 1 ]; then
		log "  backup: full /overlay dump..."
		"$ROOT_DIR/scripts/backup_overlay.sh" "$ip" "$BACKUP_DIR" \
			|| warn "backup failed for $ip"
	fi

	# Overlay/opt files, common -> camera -> device (later wins).
	for layer in "${layers[@]}"; do
		apply_overlay_layer "$layer" overlay / || status=1
		apply_overlay_layer "$layer" opt /opt || status=1
	done

	# JSON partials, same precedence order.
	changed_prudynt=0
	for layer in "${layers[@]}"; do
		if [ -s "$layer/thingino.json" ]; then
			import_json /etc/thingino.json "$layer/thingino.json" || status=1
		fi
		if [ -s "$layer/prudynt.json" ]; then
			import_json /etc/prudynt.json "$layer/prudynt.json" || status=1
			changed_prudynt=1
		fi
	done

	if [ "$DRY_RUN" -eq 0 ] && [ "$changed_prudynt" -eq 1 ]; then
		restart_prudynt || true
	fi

	if [ "$DRY_RUN" -eq 0 ] && [ "$DO_REBOOT" -eq 1 ]; then
		log "  rebooting camera..."
		rsh "reboot -f" || true
	fi

	[ "$status" -eq 0 ] || warn "some steps failed for $ip"
	return "$status"
}

failures=0
count=0

# Expand any from-to address ranges in the -i/positional inputs.
# Runs here, after the helper functions are defined.
mapfile -t IPS < <(for ip in "${IPS[@]}"; do expand_ip "$ip"; done)

if [ -n "$ROSTER" ]; then
	[ -f "$ROSTER" ] || die "roster file not found: $ROSTER"
	log "Using roster: $ROSTER"
	while IFS= read -r entry; do
		entry="$(printf '%s' "$entry" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
		[ -n "$entry" ] || continue
		case "$entry" in
			\#*) continue ;;
		esac
		# A roster line may be a single address or a from-to range.
		while IFS= read -r ip; do
			count=$((count + 1))
			apply_camera "$ip" || failures=$((failures + 1))
		done < <(expand_ip "$entry")
	done < "$ROSTER"
else
	[ "${#IPS[@]}" -gt 0 ] || usage 1
	for ip in "${IPS[@]}"; do
		count=$((count + 1))
		apply_camera "$ip" || failures=$((failures + 1))
	done
fi

log ""
log "Processed $count camera(s), $failures failure(s)."
[ "$failures" -eq 0 ]
