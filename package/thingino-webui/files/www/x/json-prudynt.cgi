#!/bin/sh
# BusyBox httpd CGI for JSON API
# Expects request body (application/json)

# Check authentication
. /var/www/x/auth.sh
require_auth

echo "Content-Type: application/json"
echo

# Read exactly CONTENT_LENGTH bytes if provided; otherwise read all stdin
if [ -n "$CONTENT_LENGTH" ]; then
  dd bs=1 count="$CONTENT_LENGTH" 2>/dev/null | prudyntctl json -
else
  prudyntctl json -
fi
