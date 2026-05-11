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
	printf 'Cache-Control: no-store\r\n'
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

# @params: n - name, s - state
if [ "$REQUEST_METHOD" = "POST" ]; then
	if [ -n "$CONTENT_LENGTH" ] && [ "$CONTENT_LENGTH" -gt 0 ]; then
		CONTENT=$(dd bs=1 count="$CONTENT_LENGTH" 2>/dev/null)
		eval $(echo "$CONTENT" | sed "s/&/;/g")
	fi
else
	eval $(echo "$QUERY_STRING" | sed "s/&/;/g")
fi

[ -z "$n" ] && json_error "Required parameter 'n' is not set"

if [ -d "/sys/class/leds/$n" ]; then
	trigger_file="/sys/class/leds/$n/trigger"
	brightness_file="/sys/class/leds/$n/brightness"
	max_brightness=$(cat "/sys/class/leds/$n/max_brightness" 2>/dev/null)
	case "$max_brightness" in
		'' | *[!0-9]*) max_brightness=255 ;;
	esac
	[ -w "$trigger_file" ] && printf 'none\n' >"$trigger_file"
	case "$s" in
		0)
			state=0
			printf '0\n' >"$brightness_file"
			;;
		1)
			state=1
			printf '%s\n' "$max_brightness" >"$brightness_file"
			;;
		*)
			current=$(cat "$brightness_file" 2>/dev/null)
			case "$current" in
				'' | *[!0-9]*) current=0 ;;
			esac
			if [ "$current" -gt 0 ]; then
				printf '0\n' >"$brightness_file"
			else
				printf '%s\n' "$max_brightness" >"$brightness_file"
			fi
			state='"toggled"'
			;;
	esac
	printf 'Status: 200 OK\r\nContent-Type: application/json\r\nCache-Control: no-store\r\n\r\n{"pin":"%s","status":%s}\n' "$n" "$state"
	exit 0
fi

# Read GPIO pin from configuration file using jct (faster than grep)
pin=$(jct /etc/thingino.json get gpio."$n".pin 2>/dev/null || jct /etc/thingino.json get gpio."$n" 2>/dev/null)
[ -z "$pin" ] && json_error "GPIO '$n' is not configured"

case "$s" in
	0)
		state=0
		gpio set "$pin" "$state"
		;;
	1)
		state=1
		gpio set "$pin" "$state"
		;;
	*)
		state='"toggled"'
		gpio toggle "$pin"
		;;
esac

# Return immediately without verification
printf 'Status: 200 OK\r\nContent-Type: application/json\r\nCache-Control: no-store\r\n\r\n{"pin":"%s","status":%s}\n' "$pin" "$state"
