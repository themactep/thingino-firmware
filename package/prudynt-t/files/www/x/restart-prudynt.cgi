#!/bin/sh
# Restart prudynt service

# Check authentication
# shellcheck disable=SC1091  # auth.sh is installed on the camera, not in the build tree
. /var/www/x/auth.sh
require_auth

echo "Content-Type: application/json"
echo "Connection: close"
echo
echo '{"status":"ok","message":"Prudynt restart initiated"}'

service restart prudynt >/dev/null 2>&1 &
