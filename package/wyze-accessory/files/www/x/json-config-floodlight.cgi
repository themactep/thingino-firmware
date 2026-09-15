#!/bin/sh
# Authenticated status and control endpoint for the Wyze Floodlight v1.
. /var/www/x/auth.sh
require_auth

CTL=/usr/sbin/floodlight_ctl
STATE_FILE=/var/run/floodlight.status
BRIGHTNESS_FILE=/var/run/floodlight.brightness
MOTION_CONFIG=/etc/floodlight-motion.conf
REQ_FILE=""

cleanup() { [ -n "$REQ_FILE" ] && rm -f "$REQ_FILE"; }
trap cleanup EXIT

send_json() {
	printf 'Status: %s\nContent-Type: application/json\nCache-Control: no-store\nPragma: no-cache\nConnection: close\n\n%s\n' "${2:-200 OK}" "$1"
	exit 0
}

motion_settings_json() {
	motion_enabled=0
	motion_duration=30
	if [ -r "$MOTION_CONFIG" ]; then
		value=$(sed -n 's/^MOTION_ENABLED=\([01]\)$/\1/p' "$MOTION_CONFIG" | head -n 1)
		[ -n "$value" ] && motion_enabled=$value
		value=$(sed -n 's/^MOTION_DURATION=\([0-9][0-9]*\)$/\1/p' "$MOTION_CONFIG" | head -n 1)
		[ -n "$value" ] && motion_duration=$value
	fi
	case "$motion_duration" in '' | *[!0-9]*) motion_duration=30 ;; esac
	[ "$motion_duration" -ge 1 ] && [ "$motion_duration" -le 3600 ] || motion_duration=30
	printf '%s %s' "$motion_enabled" "$motion_duration"
}

save_motion_settings() {
	rm -rf /var/run/floodlight-motion.lock
	case "$1" in true) motion_enabled=1 ;; false) motion_enabled=0 ;; *) return 1 ;; esac
	case "$2" in '' | *[!0-9]*) return 1 ;; esac
	[ "$2" -ge 1 ] && [ "$2" -le 3600 ] || return 1
	tmp=$(mktemp /etc/floodlight-motion.XXXXXX) || return 1
	printf 'MOTION_ENABLED=%s\nMOTION_DURATION=%s\n' "$motion_enabled" "$2" >"$tmp" || { rm -f "$tmp"; return 1; }
	chmod 600 "$tmp" && mv "$tmp" "$MOTION_CONFIG"
}

status_json() {
	available=false
	[ -x "$CTL" ] && { [ -c /dev/ttyUSB0 ] || [ -c /dev/ttyUSB1 ]; } && available=true
	state=OFF
	[ -f "$STATE_FILE" ] && IFS= read -r state <"$STATE_FILE"
	case "$state" in ON | OFF) ;; *) state=OFF ;; esac
	brightness=100
	if [ -f "$BRIGHTNESS_FILE" ]; then
		IFS= read -r brightness <"$BRIGHTNESS_FILE"
	fi
	case "$brightness" in '' | *[!0-9]*) brightness=100 ;; esac
	[ "$brightness" -ge 1 ] && [ "$brightness" -le 100 ] || brightness=100
	set -- $(motion_settings_json)
	[ "$1" = 1 ] && motion_enabled=true || motion_enabled=false
	printf '{"available":%s,"state":"%s","brightness":%s,"motion_enabled":%s,"motion_duration":%s}' "$available" "$state" "$brightness" "$motion_enabled" "$2"
}

case "$REQUEST_METHOD" in
	GET | "") send_json "$(status_json)" ;;
	POST)
		REQ_FILE=$(mktemp /tmp/floodlight-req.XXXXXX) || send_json '{"error":{"message":"Cannot read request"}}' '500 Internal Server Error'
		if [ -n "$CONTENT_LENGTH" ]; then dd bs=1 count="$CONTENT_LENGTH" 2>/dev/null >"$REQ_FILE"; else cat >"$REQ_FILE"; fi
		action=$(sed -n 's/.*"action"[[:space:]]*:[[:space:]]*"\([a-z-]*\)".*/\1/p' "$REQ_FILE" | head -n 1)
		brightness=$(sed -n 's/.*"brightness"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$REQ_FILE" | head -n 1)
		case "$action" in
			on)
				case "$brightness" in '' | *[!0-9]*) send_json '{"error":{"message":"Brightness must be 1-100"}}' '422 Unprocessable Entity' ;; esac
				[ "$brightness" -ge 1 ] && [ "$brightness" -le 100 ] || send_json '{"error":{"message":"Brightness must be 1-100"}}' '422 Unprocessable Entity'
				"$CTL" on "$brightness" >/dev/null 2>&1 || send_json '{"error":{"message":"Floodlight controller is unavailable"}}' '503 Service Unavailable'
				;;
			off) "$CTL" off >/dev/null 2>&1 || send_json '{"error":{"message":"Floodlight controller is unavailable"}}' '503 Service Unavailable' ;;
			motion-settings)
				motion_enabled=$(sed -n 's/.*"motion_enabled"[[:space:]]*:[[:space:]]*\(true\|false\).*/\1/p' "$REQ_FILE" | head -n 1)
				motion_duration=$(sed -n 's/.*"motion_duration"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$REQ_FILE" | head -n 1)
				save_motion_settings "$motion_enabled" "$motion_duration" || send_json '{"error":{"message":"Motion settings must use a duration from 1 to 3600 seconds"}}' '422 Unprocessable Entity'
				;;
			*) send_json '{"error":{"message":"Invalid floodlight action"}}' '422 Unprocessable Entity' ;;
		esac
		send_json "$(status_json)"
		;;
	*) send_json '{"error":{"message":"Method not allowed"}}' '405 Method Not Allowed' ;;
esac
