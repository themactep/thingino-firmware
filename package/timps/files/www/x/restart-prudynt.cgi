#!/bin/sh
# shellcheck disable=SC1091

# Check authentication
. /var/www/x/auth.sh
require_auth

echo "Content-Type: application/json"
echo "Connection: close"
echo
echo '{"status":"ok","message":"Streamer (timps) restart initiated"}'

/etc/init.d/S95timps restart >/dev/null 2>&1 &
