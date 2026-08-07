#!/bin/sh
# Persist streamer configuration in a streamer-aware way.

. /var/www/x/auth.sh
require_auth

json_header() {
	printf 'Status: 200 OK\r\n'
	printf 'Content-Type: application/json\r\n'
	printf 'Cache-Control: no-store\r\n'
	printf 'Connection: close\r\n'
	printf '\r\n'
}

json_error() {
	printf 'Status: %s\r\n' "${2:-500 Internal Server Error}"
	printf 'Content-Type: application/json\r\n'
	printf 'Cache-Control: no-store\r\n'
	printf 'Connection: close\r\n'
	printf '\r\n'
	printf '{"error":{"message":"%s"}}\n' "$(printf '%s' "$1" | sed 's/"/\\"/g')"
	exit 0
}

streamer="prudynt"
if [ -r /etc/thingino-streamer ]; then
	streamer=$(sed -n '1p' /etc/thingino-streamer 2>/dev/null | tr -d '\r\n ')
fi
case "$streamer" in
	raptor | prudynt | strero | timps | none) ;;
	*)
		if [ -f /etc/raptor.conf ] && command -v raptorctl >/dev/null 2>&1; then
			streamer=raptor
		elif [ -f /etc/prudynt.json ]; then
			streamer=prudynt
		fi
		;;
esac

case "$streamer" in
	raptor)
		command -v raptorctl >/dev/null 2>&1 || json_error "raptorctl not available"
		raptorctl config save >/dev/null 2>&1 || json_error "raptor config save failed"
		json_header
		printf '{"status":"ok","streamer":"raptor","path":"/etc/raptor.conf"}\n'
		;;
	prudynt)
		command -v prudyntctl >/dev/null 2>&1 || json_error "prudyntctl not available"
		echo '{"action":{"save_config":null}}' | prudyntctl json - >/dev/null 2>&1 || json_error "prudynt save_config failed"
		json_header
		printf '{"status":"ok","streamer":"prudynt","path":"/etc/prudynt.json","action":{"save_config":"ok"}}\n'
		;;
	*)
		json_error "unsupported streamer for save: $streamer" "400 Bad Request"
		;;
esac
