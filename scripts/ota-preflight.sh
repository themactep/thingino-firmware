#!/usr/bin/env bash
# ota-preflight.sh - verify a camera's WiFi config against what an OTA WOULD
# push, before the OTA is flashed.
#
# THE PROBLEM. An OTA overwrites /etc, including wpa_supplicant.conf. The
# image is built from user/<board>/<ip>/overlay/... (device-specific) layered
# over user/<board>/overlay/... (board-wide) layered over
# user/common/overlay/... (fleet-wide) - see the THINGINO_USER_OVERLAY_DIRS /
# BR2_ROOTFS_OVERLAY logic in the top-level Makefile, later dirs win. If the
# WiFi block that would land on the camera does not match what the camera is
# actually associated with right now, the camera comes back up on the wrong
# network (or with the wrong password) and is unreachable - no SSH, no way to
# push a fix. For a camera mounted on an outdoor wall, "unreachable" means
# fetching a ladder and physically pulling it down to recover it. This script
# is the check that used to be done by hand, one camera at a time, before
# every flash.
#
# RESOLUTION ORDER (must mirror the Makefile exactly, or this tool lies):
#   1. user/<board>/<ip>/overlay/etc/wpa_supplicant.conf   (device-specific)
#   2. user/<board>/overlay/etc/wpa_supplicant.conf        (board-wide)
#   3. user/common/overlay/etc/wpa_supplicant.conf         (fleet-wide)
# <board> is found from <ip> by searching the repo for a directory literally
# named <ip> one level below user/ - that IS how the build ties an IP to a
# board (CAMERA_IP_ADDRESS becomes THINGINO_USER_DEVICE_DIR), so it is also
# how this script finds it. No SSH round trip is needed for this half of the
# job; it is a pure repo lookup.
#
# On this fleet only tiers 1 and 3 are ever populated (no board-wide
# wpa_supplicant.conf exists yet) - which means 5 of 12 cameras currently
# share ONE file. Change that file and all 5 drop off the network at once,
# discovered only after the flash is already out. This script reports that
# exposure explicitly (source=common-fallback, with the sibling IPs that ride
# on the same file) rather than silently confirming "OK" and hiding it.
#
# SECURITY. A PSK is a live WiFi credential. It is NEVER printed in plaintext,
# on either side of the comparison - only as `sha256("psk=" line) | cut -c1-16`,
# exactly as verified by hand: grep -oE 'psk=.*' FILE | sha256sum | cut -c1-16
# The output of this script is expected to end up in logs/chat, and a
# truncated hash is not a secret.
#
#   ./scripts/ota-preflight.sh check <ip>...   # the only subcommand
#
# Exit status: 0 iff every camera checked matches (safe to flash all of
# them); 1 if any camera is unreachable, unresolvable, or mismatched. Meant
# to gate a flash: `ota-preflight.sh check $ALL_IPS && make ota-all` (or
# whatever the fleet's flash step is called).
#
# This script runs on the Linux HOST, not on the camera - plain bash is fine.
set -uo pipefail

SSH="ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=4"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
USER_DIR="$REPO_ROOT/user"
COMMON_WPA="$USER_DIR/common/overlay/etc/wpa_supplicant.conf"

CMD="${1:-}"; shift || true

# --- helpers -----------------------------------------------------------

# sha256("psk=..." line), truncated - never the PSK itself.
psk_hash() {
    grep -oE 'psk=.*' 2>/dev/null | sha256sum | cut -c1-16
}

# SSID value only (quotes stripped) - not sensitive, printed as-is.
ssid_of() {
    grep -oE 'ssid="[^"]*"' 2>/dev/null | head -1 | sed 's/^ssid="//; s/"$//'
}

# Locate user/<board>/<ip> for an IP - the same link the Makefile uses
# (CAMERA_IP_ADDRESS -> THINGINO_USER_DEVICE_DIR). Prints the DEVICE dir, not
# the board dir; the board name is its parent. Empty if no directory matches.
device_dir_for_ip() {
    local ip="$1"
    # -L is load-bearing: in a linked worktree user/ is a symlink to the main
    # checkout's fleet dir (the fleet config is shared, not duplicated), and a
    # bare find would not descend into it - every camera would then fall
    # through to common-fallback and the tool would confidently report the
    # wrong source. The -f tests elsewhere already follow symlinks.
    find -L "$USER_DIR" -mindepth 2 -maxdepth 2 -type d -name "$ip" 2>/dev/null | head -1
}

# Resolve which overlay file would supply this IP's wpa_supplicant.conf on an
# OTA, applying device > board > common precedence. Prints two lines:
#   <path or "-">
#   <tag: own-overlay | board-overlay | common-fallback | unresolved>
resolve_repo_wpa() {
    local ip="$1" device_dir board_dir f
    device_dir=$(device_dir_for_ip "$ip")

    if [ -n "$device_dir" ]; then
        f="$device_dir/overlay/etc/wpa_supplicant.conf"
        if [ -f "$f" ]; then
            printf '%s\nown-overlay\n' "$f"
            return 0
        fi
        board_dir=$(dirname "$device_dir")
        f="$board_dir/overlay/etc/wpa_supplicant.conf"
        if [ -f "$f" ]; then
            printf '%s\nboard-overlay\n' "$f"
            return 0
        fi
    fi

    if [ -f "$COMMON_WPA" ]; then
        printf '%s\ncommon-fallback\n' "$COMMON_WPA"
        return 0
    fi

    printf '-\nunresolved\n'
    return 1
}

# Every IP (from the current invocation) that would resolve to the same
# common overlay file - i.e. the blast radius if that shared file changes.
# $1: the ip being reported on; $@ (rest): the full IP list of this run.
common_siblings() {
    local self="$1"; shift
    local ip out="" device_dir
    for ip; do
        [ "$ip" = "$self" ] && continue
        device_dir=$(device_dir_for_ip "$ip")
        if [ -n "$device_dir" ] && [ -f "$device_dir/overlay/etc/wpa_supplicant.conf" ]; then
            continue
        fi
        out="${out:+$out }$ip"
    done
    printf '%s' "$out"
}

# --- core check ----------------------------------------------------------

check_one() {
    local ip="$1"; shift
    local all_ips=("$@")
    local repo_wpa tag device_dir board_name live hostname resolved
    local repo_ssid repo_pskhash live_ssid live_pskhash

    resolved=$(resolve_repo_wpa "$ip")
    repo_wpa=$(printf '%s\n' "$resolved" | sed -n '1p')
    tag=$(printf '%s\n' "$resolved" | sed -n '2p')

    device_dir=$(device_dir_for_ip "$ip")
    if [ -n "$device_dir" ]; then
        board_name=$(basename "$(dirname "$device_dir")")
    else
        board_name="UNKNOWN (no user/<board>/$ip in repo)"
    fi

    if [ "$tag" = "unresolved" ]; then
        printf '!! %-16s board=%s  no overlay resolves for this IP at all (not even common) -- FIX THE REPO, not just this camera\n' "$ip" "$board_name"
        return 1
    fi

    live=$($SSH "root@$ip" 'cat /etc/wpa_supplicant.conf 2>/dev/null; echo; echo "==HOSTNAME=="; cat /etc/hostname 2>/dev/null')
    if [ -z "$live" ]; then
        printf '!! %-16s board=%-32s UNREACHABLE (ssh failed) -- cannot verify, treat as at-risk\n' "$ip" "$board_name"
        return 1
    fi
    hostname=$(printf '%s\n' "$live" | sed -n '/==HOSTNAME==/,$p' | tail -n +2)
    live=$(printf '%s\n' "$live" | sed '/==HOSTNAME==/,$d')

    repo_ssid=$(ssid_of < "$repo_wpa")
    repo_pskhash=$(psk_hash < "$repo_wpa")
    live_ssid=$(printf '%s\n' "$live" | ssid_of)
    live_pskhash=$(printf '%s\n' "$live" | psk_hash)

    local src_note
    case "$tag" in
        own-overlay)     src_note="own overlay ($repo_wpa)" ;;
        board-overlay)   src_note="board-wide overlay ($repo_wpa)" ;;
        common-fallback)
            local sibs
            sibs=$(common_siblings "$ip" "${all_ips[@]}")
            src_note="SHARED common overlay ($repo_wpa)"
            [ -n "$sibs" ] && src_note="$src_note -- also covers: $sibs"
            ;;
    esac

    if [ "$repo_ssid" = "$live_ssid" ] && [ "$repo_pskhash" = "$live_pskhash" ] && [ -n "$live_ssid" ]; then
        printf 'OK  %-16s board=%-32s host=%-16s ssid=%-12s source=%s\n' \
            "$ip" "$board_name" "$hostname" "$live_ssid" "$src_note"
        return 0
    else
        printf '!! %-16s board=%-32s host=%-16s MISMATCH -- OTA would break this camera'\''s network\n' \
            "$ip" "$board_name" "$hostname"
        printf '     live:  ssid=%s psk_sha256_16=%s\n' "${live_ssid:-<none found>}" "${live_pskhash:-<none>}"
        printf '     image: ssid=%s psk_sha256_16=%s   (from %s)\n' "${repo_ssid:-<none found>}" "${repo_pskhash:-<none>}" "$src_note"
        return 1
    fi
}

# --- dispatch --------------------------------------------------------------

case "$CMD" in
    check)
        [ "$#" -ge 1 ] || { echo "usage: $0 check <ip>..." >&2; exit 1; }
        fail=0
        for ip; do
            check_one "$ip" "$@" || fail=1
        done
        exit "$fail"
        ;;
    *)
        # the header block is the help text; drop the shebang, which would
        # otherwise print as a stray "!/usr/bin/env bash" first line
        grep '^#' "$0" | grep -v '^#!' | sed 's/^# \{0,1\}//'
        exit 1
        ;;
esac
