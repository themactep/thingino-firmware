#!/bin/sh
# shellcheck disable=SC1091

. /var/www/x/auth.sh
require_auth

printf 'Content-Type: application/json\r\n'
printf 'Cache-Control: no-store\r\n'
printf 'Connection: close\r\n'
printf '\r\n'
raptorctl rtd status 2>/dev/null || printf '{"status":"error"}\n'
