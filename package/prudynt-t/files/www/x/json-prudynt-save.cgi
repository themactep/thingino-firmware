#!/bin/sh
# shellcheck disable=SC1091

# Apply configuration through prudynt, which persists the deltas to the
# writable user layer (/etc/prudynt.user.json). The read-only core
# (/etc/prudynt.json) is never written.

. /var/www/x/auth.sh
require_auth

TEMP_FILE="/tmp/prudynt-save-$$.json"

http_200() {
	printf 'Status: 200 OK\r\n'
}

send_headers() {
	http_200
	printf 'Content-Type: application/json\r\nConnection: close\r\n\r\n'
}

error_response() {
	send_headers
	printf '{"error":"%s"}\n' "$1"
	rm -f "$TEMP_FILE"
	exit 1
}

# Read POST body from stdin
if [ -z "$CONTENT_LENGTH" ] || [ "$CONTENT_LENGTH" -eq 0 ]; then
	error_response "No payload provided"
fi

# Read the JSON payload
cat >"$TEMP_FILE"

# Check if file was created and has content
if [ ! -s "$TEMP_FILE" ]; then
	error_response "Empty payload received"
fi

if ! prudyntctl json - <"$TEMP_FILE" >/dev/null 2>&1; then
	error_response "Failed to apply configuration"
fi

rm -f "$TEMP_FILE"

send_headers
printf '{"status":"ok","message":"Configuration saved"}\n'
