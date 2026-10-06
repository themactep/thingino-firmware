#!/bin/sh
# shellcheck disable=SC1091
#
# json-lamp-socket.cgi - Wyze Lamp Socket status, control and settings
# POST actions: on, off, toggle, query, send (bytes),
#               save (enabled, boot_state, device)
#

. /var/www/x/auth.sh
require_auth

CONFIG_FILE="/etc/thingino.json"
CTL="/usr/sbin/lamp_socket_ctl"

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

cfg() {
	jct "$CONFIG_FILE" get "lamp_socket.$1" 2>/dev/null | tr -d '"' | grep -v '^null$'
}

is_enabled() {
	[ "$(cfg enabled)" = "true" ]
}

handle_get() {
	device=$("$CTL" device 2>/dev/null)
	if [ -n "$device" ]; then
		present=true
	else
		present=false
	fi
	if is_enabled; then
		enabled=true
		[ "$present" = "true" ] && state=$("$CTL" status 2>/dev/null)
	else
		enabled=false
	fi
	boot_state=$(cfg boot_state)
	send_json "{\"enabled\":$enabled,\"present\":$present,\"device\":\"$(json_escape "$device")\",\"device_override\":\"$(json_escape "$(cfg device)")\",\"state\":\"${state:-unknown}\",\"boot_state\":\"${boot_state:-none}\"}"
}

read_body() {
	case "$CONTENT_LENGTH" in
		*[!0-9]*) json_error 400 "Invalid Content-Length" ;;
	esac
	REQ_FILE=$(mktemp /tmp/lamp-socket-req.XXXXXX)
	trap 'rm -f "$REQ_FILE"' EXIT
	if [ -n "$CONTENT_LENGTH" ] && [ "$CONTENT_LENGTH" -gt 0 ]; then
		dd bs=1 count="$CONTENT_LENGTH" 2>/dev/null >"$REQ_FILE"
	else
		cat >"$REQ_FILE"
	fi
}

get_field() {
	jct "$REQ_FILE" get "$1" 2>/dev/null | tr -d '"' | tr -d '\r\n'
}

run_ctl() {
	output=$("$CTL" "$@" 2>&1)
	rc=$?
	[ $rc -eq 0 ] || json_error 503 "$output" "503 Service Unavailable"
}

do_save() {
	enabled=$(get_field enabled)
	boot_state=$(get_field boot_state)
	device=$(get_field device)
	case "$enabled" in
		true | false) ;;
		*) json_error 400 "enabled must be true or false" ;;
	esac
	case "$boot_state" in
		on | off | last | none) ;;
		*) json_error 400 "boot_state must be on, off, last or none" ;;
	esac
	if [ -n "$device" ]; then
		# Only /dev/tty followed by letters and digits, e.g. /dev/ttyUSB0.
		case "${device#/dev/tty}" in
			"" | "$device" | *[!A-Za-z0-9]*) json_error 400 "device must be empty or a /dev/tty* device name" ;;
		esac
	fi
	was_enabled=$(cfg enabled)
	jct "$CONFIG_FILE" set lamp_socket.enabled "$enabled" >/dev/null 2>&1
	jct "$CONFIG_FILE" set lamp_socket.boot_state "$boot_state" >/dev/null 2>&1
	jct "$CONFIG_FILE" set lamp_socket.device "$device" >/dev/null 2>&1
	# Seed last_state so "last" survives a reboot even before the next toggle.
	if [ "$enabled" = "true" ] && [ "$boot_state" = "last" ]; then
		state=$("$CTL" status 2>/dev/null)
		case "$state" in
			on | off) jct "$CONFIG_FILE" set lamp_socket.last_state "$state" >/dev/null 2>&1 ;;
		esac
	fi
	# Republish Home Assistant discovery so the Lamp switch appears or goes away.
	if [ "$was_enabled" != "$enabled" ] && [ -x /etc/init.d/S93ha ] &&
		[ "$(jct "$CONFIG_FILE" get ha.enabled 2>/dev/null)" = "true" ]; then
		/etc/init.d/S93ha restart >/dev/null 2>&1 &
	fi
	send_json '{"status":"ok"}'
}

handle_post() {
	read_body
	action=$(get_field action)
	case "$action" in
		on | off | toggle)
			is_enabled || json_error 409 "Lamp Socket is disabled" "409 Conflict"
			run_ctl "$action"
			send_json "{\"status\":\"ok\",\"state\":\"$(json_escape "$output")\"}"
			;;
		query)
			run_ctl query
			send_json "{\"status\":\"ok\",\"reply\":\"$(json_escape "$output")\"}"
			;;
		send)
			bytes=$(get_field bytes)
			case "$bytes" in
				"" | *[!0-9a-fA-Fx\ ]*) json_error 400 "bytes must be space-separated 0xNN or decimal values" ;;
			esac
			# shellcheck disable=SC2086
			run_ctl send $bytes
			send_json "{\"status\":\"ok\",\"reply\":\"$(json_escape "$output")\"}"
			;;
		save)
			do_save
			;;
		*)
			json_error 400 "Unknown action"
			;;
	esac
}

case "$REQUEST_METHOD" in
	GET) handle_get ;;
	POST) handle_post ;;
	*) json_error 405 "Method not allowed" "405 Method Not Allowed" ;;
esac
