#!/bin/sh
# Persist raptor configuration via raptorctl.

# shellcheck disable=SC1091  # auth.sh is installed on the camera, not in the build tree
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

command -v raptorctl >/dev/null 2>&1 || json_error "raptorctl not available"
raptorctl config save >/dev/null 2>&1 || json_error "raptor config save failed"
json_header
printf '{"status":"ok","path":"/etc/raptor.conf"}\n'
