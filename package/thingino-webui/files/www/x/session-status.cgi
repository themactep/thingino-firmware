#!/bin/sh

. /var/www/x/session.sh

send_json() {
  printf "Content-Type: application/json\r\n"
  printf "Cache-Control: no-store\r\n"
  printf "\r\n"
  printf "%s\n" "$1"
}

# Get session from cookie
session_id=$(get_session_from_cookie)

if [ -n "$session_id" ] && validate_session "$session_id"; then
  # Session is valid
  username=$(get_session_data "$session_id" "username")
  is_default=$(get_session_data "$session_id" "is_default_password")

  send_json "{\"authenticated\":true,\"username\":\"$username\",\"is_default_password\":$is_default}"
else
  # Not authenticated
  send_json "{\"authenticated\":false}"
fi
