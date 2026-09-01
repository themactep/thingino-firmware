#!/bin/sh
# shellcheck disable=SC1091,SC2046,SC2317,SC2329,SC3043

# Check authentication
. /var/www/x/auth.sh
require_auth

http_200() {
	printf 'Status: 200 OK\r\n'
}

http_400() {
	printf 'Status: 400 Bad Request\r\n'
}

http_412() {
	printf 'Status: 412 Precondition Failed\r\n'
}

json_header() {
	printf 'Content-Type: application/json\r\n'
	printf 'Pragma: no-cache\r\n'
	printf 'Expires: %s\r\n' "$(TZ=GMT0 date +'%a, %d %b %Y %T %Z')"
	printf 'Etag: "%s"\r\n' "$(cat /proc/sys/kernel/random/uuid)"
	printf 'Connection: close\r\n'
	printf '\r\n'
}

json_error() {
	http_412
	json_header
	printf '{"error":{"code":412,"message":"%s"}}
' "$1"
	exit 0
}

json_ok() {
	http_200
	json_header
	if [ "{" = "$(printf '%.1s' "$1")" ]; then
		printf '{"code":200,"result":"success","message":%s}
' "$1"
	else
		printf '{"code":200,"result":"success","message":"%s"}
' "$1"
	fi
	exit 0
}

[ -n "$QUERY_STRING" ] && eval $(echo "$QUERY_STRING" | sed "s/&/;/g")

# URL-decode string params (description, n); the rest are numeric/single char.
urldecode() {
	printf '%b' "$(echo "$1" | sed 's/+/ /g; s/%\([0-9A-Fa-f][0-9A-Fa-f]\)/\\x\1/g')"
}
[ -n "$description" ] && description=$(urldecode "$description")
[ -n "$n" ] && n=$(urldecode "$n")
[ -n "$order" ] && order=$(urldecode "$order")

json_escape() {
	printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

[ -z "$x" ] && x=0
[ -z "$y" ] && y=0
[ -z "$d" ] && d="g"

# Motion commands answer with a bare acknowledgement.
#
# They used to fall through to a trailing emit_status that ran `motors -j` and
# returned the position with every single move. That echo made sense when this
# CGI was the only way to drive the motors and the page had no other source of
# position - but it doubled the process cost of the hottest path in the whole
# UI: a held arrow fired one of these every 90ms, and each one paid for
# busybox-httpd, this shell, `motors`, and then a SECOND `motors` purely to
# report a position that was already stale by the time it was read (the move
# is asynchronous; the daemon has not finished it when the status is sampled).
#
# preview-motors.js tracks position client-side from the moves it issues and
# only ever console.log()s this echo, so dropping it costs nothing there.
# Callers that actually want a fresh position ask for one explicitly with d=j.
motion_ok() {
	json_ok "$1"
}

case "$d" in
	g)
		# Relative jog - the joystick's per-step move.
		motors -d g -x "$x" -y "$y" >/dev/null
		motion_ok "moved"
		;;
	r)
		# Homing / recalibration - a one-shot maintenance action, not a hold
		# gesture, and it runs for tens of seconds.
		motors -r >/dev/null
		motion_ok "homing"
		;;
	h | x)
		# Absolute move - used for centring, the reposition after homing, and
		# preset jumps issued from the page.
		motors -d h -x "$x" -y "$y" >/dev/null
		motion_ok "moved"
		;;
	s)
		# Stop - halts an in-progress move; the page's release handler for a
		# held direction.
		motors -d s >/dev/null
		motion_ok "stopped"
		;;
	b)
		# Goback - a distinct driver operation (MOTOR_GOBACK). No caller in
		# this tree today; kept since removing it would be an unrelated
		# dead-code change.
		motors -d b >/dev/null
		motion_ok "goback"
		;;
	j)
		# Explicit one-shot status - config-motors.js calls it from the
		# settings page's "capture current position" button. (The 'i' case
		# that sat next to it - `motors -i`, an initial-position echo - had
		# no caller anywhere in this tree and is gone.)
		payload=$(motors -j 2>/dev/null) || json_error "motors-status-failed"
		json_ok "$payload"
		;;
	pg)
		# List PTZ presets from the motors.presets array in thingino.json:
		# [{"id":N,"description":"..","x":N,"y":N}]
		presets_json=$(jct /etc/thingino.json path '$.motors.presets[*]' --mode values 2>/dev/null)
		[ -n "$presets_json" ] || presets_json='[]'
		json_ok "{\"presets\":$presets_json}"
		;;
	ps)
		# Save current motor position as a preset (auto slot)
		[ -n "$description" ] || json_error "preset-description-required"
		output=$(ptz_presets -a -1 "$description" 2>&1) || json_error "preset-save-failed"
		json_ok "{\"status\":\"$output\"}"
		;;
	pr)
		# Move to a preset
		[ -n "$n" ] || json_error "preset-number-required"
		output=$(ptz_presets "$n" 2>&1) || json_error "preset-run-failed"
		json_ok "{\"status\":\"preset $n run\"}"
		;;
	pd)
		# Delete a preset
		[ -n "$n" ] || json_error "preset-number-required"
		ptz_presets -r "$n" >/dev/null 2>&1
		json_ok "{\"status\":\"preset $n deleted\"}"
		;;
	pu)
		# Update an existing preset's description and coordinates
		[ -n "$n" ] || json_error "preset-number-required"
		[ -n "$description" ] || json_error "preset-description-required"
		case "$x" in
			'' | *[!0-9]*) json_error "preset-x-invalid" ;;
		esac
		case "$y" in
			'' | *[!0-9]*) json_error "preset-y-invalid" ;;
		esac
		ptz_presets -a "$n" "$description" "$x" "$y" >/dev/null 2>&1 || json_error "preset-update-failed"
		json_ok "{\"status\":\"preset $n updated\"}"
		;;
	po)
		# Reorder presets: order is a comma-separated list of preset ids.
		# Ids are stable; only the array order changes.
		[ -n "$order" ] || json_error "preset-order-required"
		output=$(ptz_presets -o "$order" 2>&1) || json_error "preset-reorder-failed"
		json_ok "{\"status\":\"$output\"}"
		;;
	*)
		json_error "motors-command-unsupported"
		;;
esac

# Every case above exits through json_ok or json_error, so nothing reaches
# here. Reaching it at all would mean a case fell through silently.
json_error "motors-command-unhandled"
