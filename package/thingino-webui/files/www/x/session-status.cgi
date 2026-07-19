#!/bin/sh

. /var/www/x/session.sh
. /var/www/x/auth.sh

send_json() {
	printf "Content-Type: application/json\r\n"
	printf "Cache-Control: no-store\r\n"
	printf "Connection: close\r\n"
	printf "\r\n"
	printf "%s\n" "$1"
}

# Normalise client IP with shell builtins (see auth.sh)
client_ip=$(normalize_client_ip "${REMOTE_ADDR:-}")

# Trusted IP bypass - report as authenticated without a session
if is_trusted_ip; then
	send_json "{\"authenticated\":true,\"username\":\"local\",\"is_default_password\":false,\"client_ip\":\"$client_ip\"}"
	exit 0
fi

# Get session from cookie
session_id=$(get_session_from_cookie)

if [ -n "$session_id" ] && validate_session "$session_id"; then
	# Session is valid. validate_session sourced the session file - use its
	# variables directly instead of forking get_session_data subshells.
	send_json "{\"authenticated\":true,\"username\":\"$username\",\"is_default_password\":$is_default_password,\"client_ip\":\"$client_ip\"}"
else
	# Not authenticated
	send_json "{\"authenticated\":false,\"client_ip\":\"$client_ip\"}"
fi
