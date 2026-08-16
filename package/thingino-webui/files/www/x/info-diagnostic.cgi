#!/bin/sh
# shellcheck disable=SC1091,SC2317,SC3043

# Check authentication
. /var/www/x/auth.sh
require_auth

json_escape() {
	printf '%s' "$1" | sed \
		-e 's/\\/\\\\/g' \
		-e 's/"/\\"/g' \
		-e "s/\r/\\r/g" \
		-e "s/\n/\\n/g"
}

send_json() {
	local body="$1" status="${2:-200 OK}"
	printf 'Status: %s\r\n' "$status"
	printf 'Content-Type: application/json\r\n'
	printf 'Cache-Control: no-store\r\n'
	printf 'Pragma: no-cache\r\n'
	printf 'Connection: close\r\n'
	printf '\r\n'
	printf '%s\n' "$body"
	exit 0
}

json_error() {
	local code="${1:-400}"
	local message="$2"
	local status_line="${3:-400 Bad Request}"
	send_json "{\"error\":{\"code\":$code,\"message\":\"$(json_escape "$message")\"}}" "$status_line"
}

read_body() {
	if [ -n "$CONTENT_LENGTH" ]; then
		dd bs=1 count="$CONTENT_LENGTH" 2>/dev/null
	else
		cat
	fi
}

handle_post() {
	local body iagree generate_only direct_upload result
	body=$(read_body)
	[ -n "$body" ] && eval "$(echo "$body" | sed 's/&/;/g')"

	if [ "$iagree" != "true" ] && [ "$generate_only" != "true" ] && [ "$direct_upload" != "true" ]; then
		json_error 400 "You must explicitly give your consent."
	fi

	# Handle upload to server (runs thingino-diag on the backend)
	if [ "$direct_upload" = "true" ]; then
		result=$(thingino-diag -j 2>/dev/null)
		if [ -z "$result" ]; then
			json_error 500 "Failed to generate and upload diagnostic log."
		fi
		# result should be JSON from thingino-diag -j, just pass it through
		printf 'Status: 200 OK\r\n'
		printf 'Content-Type: application/json\r\n'
		printf 'Cache-Control: no-store\r\n'
		printf 'Pragma: no-cache\r\n'
		printf 'Connection: close\r\n'
		printf '\r\n'
		printf '%s\n' "$result"
		exit 0
	fi

	# Handle local generation
	if [ "$generate_only" = "true" ]; then
		# Generate diagnostic directly to stdout and encode on the fly
		local content_b64
		content_b64=$(thingino-diag -o - 2>/dev/null | base64 | tr -d '\n')

		if [ -z "$content_b64" ]; then
			json_error 500 "Failed to generate diagnostic log."
		fi

		send_json "{\"status\":\"ok\",\"output_b64\":\"$(json_escape "$content_b64")\"}"
		return
	fi

	# Original behavior - generate and upload directly
	result=$(yes yes | thingino-diag 2>&1 | tail -1)

	if [ -z "$result" ]; then
		json_error 500 "Failed to generate diagnostic log."
	fi

	if [ "${result#https://}" != "$result" ]; then
		send_json "{\"status\":\"ok\",\"link\":\"$(json_escape "$result")\"}"
	else
		send_json "{\"status\":\"ok\",\"output\":\"$(json_escape "$result")\"}"
	fi
}

case "$REQUEST_METHOD" in
	POST)
		handle_post
		;;
	GET | "")
		json_error 405 "Method not allowed" "405 Method Not Allowed"
		;;
	*)
		json_error 405 "Method not allowed" "405 Method Not Allowed"
		;;
esac
