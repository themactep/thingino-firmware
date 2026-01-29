#!/bin/sh

. /var/www/x/session.sh

# Get session from cookie
session_id=$(get_session_from_cookie)

# Delete the session
if [ -n "$session_id" ]; then
  delete_session "$session_id"
fi

# Clear the cookie and redirect to login
printf "Status: 302 Found\r\n"
printf "Location: /login.html\r\n"
printf "Set-Cookie: %s=; Path=/; Expires=Thu, 01 Jan 1970 00:00:00 GMT\r\n" "$COOKIE_NAME"
printf "Cache-Control: no-store\r\n"
printf "\r\n"
