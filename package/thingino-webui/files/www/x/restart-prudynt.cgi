#!/bin/sh
# Restart prudynt service

# Check authentication
. /var/www/x/auth.sh
require_auth

echo "Content-Type: application/json"
echo
echo '{"status":"ok","message":"Prudynt restart initiated"}'

service restart prudynt >/dev/null 2>&1 &
