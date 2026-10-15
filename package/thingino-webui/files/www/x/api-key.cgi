#!/bin/sh
# shellcheck disable=SC1091

. /var/www/x/auth.sh

# Trusted-IP bypass is handled inside require_auth; API key auth is intentionally
# excluded here (would be circular), so verify_api_key is skipped via the fallback.
session_id=$(get_session_from_cookie)
if ! is_trusted_ip && { [ -z "$session_id" ] || ! validate_session "$session_id"; }; then
	printf "Status: 401 Unauthorized\r\n"
	printf "Content-Type: application/json\r\n"
	printf "Connection: close\r\n"
	printf "\r\n"
	printf '{"error":"Session authentication required"}\n'
	exit 0
fi

API_KEY_FILE="/etc/thingino-api.key"
REQ_FILE=""

cleanup() {
	[ -n "$REQ_FILE" ] && rm -f "$REQ_FILE"
}
trap cleanup EXIT

send_json() {
	printf "Content-Type: application/json\r\n"
	printf "Cache-Control: no-store\r\n"
	printf "Connection: close\r\n"
	printf "\r\n"
	printf "%s\n" "$1"
}

send_error() {
	printf "Status: %s\r\n" "${2:-400 Bad Request}"
	printf "Content-Type: application/json\r\n"
	printf "Connection: close\r\n"
	printf "\r\n"
	printf '{"error":"%s"}\n' "$1"
	exit 0
}

read_body() {
	REQ_FILE=$(mktemp /tmp/api-key-req.XXXXXX)
	if [ -n "$CONTENT_LENGTH" ]; then
		dd bs=1 count="$CONTENT_LENGTH" 2>/dev/null >"$REQ_FILE"
	else
		cat >"$REQ_FILE"
	fi
}

case "$REQUEST_METHOD" in
	GET)
		# Show current API key (if exists)
		if [ -f "$API_KEY_FILE" ]; then
			key=$(cat "$API_KEY_FILE" 2>/dev/null | tr -d '\n\r ')
			send_json "{\"api_key\":\"$key\",\"exists\":true}"
		else
			send_json "{\"exists\":false}"
		fi
		;;

	POST)
		# Accept a user-supplied key from the request body; otherwise generate one
		provided_key=""
		if [ -n "$CONTENT_LENGTH" ]; then
			read_body
			provided_key=$(jct "$REQ_FILE" get api_key 2>/dev/null)
		fi
		provided_key=$(printf '%s' "$provided_key" | tr -d '\n\r ')
		case "$provided_key" in
			"" | null)
				new_key=$(head -c 32 /dev/urandom | hexdump -e '32/1 "%02x" "\n"')
				generated=true
				;;
			*[!A-Za-z0-9._~+/=:@-]*)
				send_error "API key contains unsupported characters" "422 Unprocessable Entity"
				;;
			*)
				new_key="$provided_key"
				generated=false
				;;
		esac
		echo "$new_key" >"$API_KEY_FILE"
		chmod 600 "$API_KEY_FILE"
		send_json "{\"api_key\":\"$new_key\",\"generated\":$generated}"
		;;

	DELETE)
		# Delete API key
		rm -f "$API_KEY_FILE"
		send_json "{\"deleted\":true}"
		;;

	*)
		printf "Status: 405 Method Not Allowed\r\n"
		printf "Content-Type: application/json\r\n"
		printf "Connection: close\r\n"
		printf "\r\n"
		printf '{"error":"Method not allowed"}\n'
		;;
esac
