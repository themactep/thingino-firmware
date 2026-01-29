#!/bin/sh

. /var/www/x/session.sh

# Get session from cookie
session_id=$(get_session_from_cookie)

if [ -n "$session_id" ] && validate_session "$session_id"; then
  # Authenticated - redirect to main app
  printf "Status: 302 Found\r\n"
  printf "Location: /preview.html\r\n"
  printf "\r\n"
else
  # Not authenticated - redirect to login
  printf "Status: 302 Found\r\n"
  printf "Location: /login.html\r\n"
  printf "\r\n"
fi
