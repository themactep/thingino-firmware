#!/bin/sh

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

normalize_message() {
	local esc
	esc=$(printf '\033')
	printf '%s\n' "$1" | tr -d '\r' | sed "s/${esc}\[[0-9;]*[A-Za-z]//g" | sed '/^[[:space:]]*$/d' | tail -n 1 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
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
	case "$1" in
		\{*)
			printf '{"code":200,"result":"success","message":%s}
' "$1"
			;;
		*)
			printf '{"code":200,"result":"success","message":"%s"}
' "$1"
			;;
	esac
	exit 0
}

[ -n "$QUERY_STRING" ] && eval $(echo "$QUERY_STRING" | sed "s/&/;/g")

[ -z "$state" ] && json_error "Missing mandatory parameter: state"

[ -z "$iface" ] && iface="wg0"

is_wg_up() {
	ip link show $iface 2>/dev/null | grep -q UP
}

wg_status() {
	is_wg_up && echo -n 1 || echo -n 0
}

run_wireguard_action() {
	local action="$1"
	local output=""

	case "$action" in
		start)
			output=$(/etc/init.d/S42wireguard force 2>&1) || {
				output=$(normalize_message "$output")
				[ -n "$output" ] || output="Failed to start WireGuard"
				json_error "$output"
			}
			;;
		stop)
			output=$(/etc/init.d/S42wireguard stop 2>&1) || {
				output=$(normalize_message "$output")
				[ -n "$output" ] || output="Failed to stop WireGuard"
				json_error "$output"
			}
			;;
	esac
}

if [ "1" = "$state" ] || [ "true" = "$state" ]; then
	is_wg_up || run_wireguard_action start
else
	is_wg_up && run_wireguard_action stop
fi

json_ok "{\"status\":$(wg_status),\"message\":\"WireGuard is $(is_wg_up && echo 'up' || echo 'down')\"}"
