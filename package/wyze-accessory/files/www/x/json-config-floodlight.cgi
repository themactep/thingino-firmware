#!/bin/sh
# shellcheck disable=SC1091,SC2329
#
# json-config-floodlight.cgi – manage the Wyze Floodlight v1 accessory
#
# GET  → returns current state and configuration
# POST → executes actions: on, off, set-brightness, set-motion
#

. /var/www/x/auth.sh
require_auth

CONFIG_FILE="/etc/thingino.json"
CTL="/usr/sbin/floodlight_ctl"
STATE_FILE="/var/run/floodlight.status"
BRIGHTNESS_FILE="/var/run/floodlight.brightness"
REQ_FILE=""

cleanup() {
	[ -n "$REQ_FILE" ] && rm -f "$REQ_FILE"
}
trap cleanup EXIT

json_escape() {
	printf '%s' "$1" | tr '\n' '\r' | sed \
		-e 's/\\/\\\\/g' \
		-e 's/"/\\"/g' \
		-e 's/\r/\\n/g'
}

send_json() {
	status="${2:-200 OK}"
	printf 'Status: %s\n' "$status"
	printf 'Content-Type: application/json\n'
	printf 'Cache-Control: no-store\n'
	printf 'Pragma: no-cache\n'
	printf 'Connection: close\n\n'
	printf '%s\n' "$1"
	exit 0
}

json_error() {
	code="${1:-400}"
	message="$2"
	send_json "{\"error\":{\"code\":$code,\"message\":\"$(json_escape "$message")\"}}" "${3:-400 Bad Request}"
}

get_config() {
	jct "$CONFIG_FILE" get "$1" 2>/dev/null | tr -d '"'
}

valid_brightness() {
	case "$1" in
		'' | *[!0-9]*) return 1 ;;
	esac
	[ "$1" -ge 1 ] && [ "$1" -le 100 ]
}

available() {
	[ -x "$CTL" ] || return 1
	for d in /dev/ttyUSB*; do
		[ -c "$d" ] && return 0
	done
	return 1
}

current_state() {
	[ -r "$STATE_FILE" ] || {
		echo OFF
		return
	}
	IFS= read -r s <"$STATE_FILE"
	case "$s" in
		ON | OFF) echo "$s" ;;
		*) echo OFF ;;
	esac
}

current_brightness() {
	b=$(get_config floodlight.brightness)
	valid_brightness "$b" && {
		echo "$b"
		return
	}
	if [ -r "$BRIGHTNESS_FILE" ]; then
		IFS= read -r b <"$BRIGHTNESS_FILE"
		valid_brightness "$b" && {
			echo "$b"
			return
		}
	fi
	echo 100
}

motion_enabled() {
	[ "$(get_config floodlight.motion.enabled)" = "true" ] && echo true || echo false
}

motion_duration() {
	d=$(get_config floodlight.motion.duration)
	case "$d" in
		'' | *[!0-9]*) d=30 ;;
	esac
	[ "$d" -ge 1 ] && [ "$d" -le 3600 ] || d=30
	echo "$d"
}

status_json() {
	avail=false
	available && avail=true
	printf '{"available":%s,"state":"%s","brightness":%s,"motion_enabled":%s,"motion_duration":%s}' \
		"$avail" "$(current_state)" "$(current_brightness)" "$(motion_enabled)" "$(motion_duration)"
}

handle_get() {
	send_json "$(status_json)"
}

read_body() {
	REQ_FILE=$(mktemp /tmp/floodlight-req.XXXXXX)
	if [ -n "$CONTENT_LENGTH" ] && [ "$CONTENT_LENGTH" -gt 0 ]; then
		dd bs=1 count="$CONTENT_LENGTH" 2>/dev/null >"$REQ_FILE"
	else
		cat >"$REQ_FILE"
	fi
}

get_field() {
	jct "$REQ_FILE" get "$1" 2>/dev/null | tr -d '"' | tr -d '\r\n'
}

do_on() {
	available || json_error 503 "Floodlight controller is not available" "503 Service Unavailable"
	"$CTL" on >/dev/null 2>&1 || json_error 503 "Floodlight command failed" "503 Service Unavailable"
}

do_off() {
	available || json_error 503 "Floodlight controller is not available" "503 Service Unavailable"
	"$CTL" off >/dev/null 2>&1 || json_error 503 "Floodlight command failed" "503 Service Unavailable"
}

do_set_brightness() {
	brightness=$(get_field brightness)
	valid_brightness "$brightness" || json_error 422 "Brightness must be 1-100" "422 Unprocessable Entity"
	jct "$CONFIG_FILE" set floodlight.brightness "$brightness" >/dev/null 2>&1
	if [ "$(current_state)" = "ON" ]; then
		available || json_error 503 "Floodlight controller is not available" "503 Service Unavailable"
		"$CTL" on "$brightness" >/dev/null 2>&1 || json_error 503 "Floodlight command failed" "503 Service Unavailable"
	fi
}

do_set_motion() {
	enabled=$(get_field enabled)
	duration=$(get_field duration)
	case "$enabled" in
		true | false) ;;
		*) json_error 422 "Motion enabled must be true or false" "422 Unprocessable Entity" ;;
	esac
	case "$duration" in
		'' | *[!0-9]*) json_error 422 "Motion duration must be a number" "422 Unprocessable Entity" ;;
	esac
	[ "$duration" -ge 1 ] && [ "$duration" -le 3600 ] || json_error 422 "Motion duration must be 1-3600 seconds" "422 Unprocessable Entity"
	jct "$CONFIG_FILE" set floodlight.motion.enabled "$enabled" >/dev/null 2>&1
	jct "$CONFIG_FILE" set floodlight.motion.duration "$duration" >/dev/null 2>&1
}

if [ "$REQUEST_METHOD" = "GET" ] || [ -z "$REQUEST_METHOD" ]; then
	handle_get
elif [ "$REQUEST_METHOD" = "POST" ]; then
	read_body
	action=$(get_field action)
	case "$action" in
		on) do_on ;;
		off) do_off ;;
		set-brightness) do_set_brightness ;;
		set-motion) do_set_motion ;;
		*) json_error 400 "Unknown action: $action" ;;
	esac
	send_json "$(status_json)"
else
	json_error 405 "Method not allowed" "405 Method Not Allowed"
fi
