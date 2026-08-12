#!/bin/sh
# Restart prudynt service and redirect back

# Check authentication
. /var/www/x/auth.sh
require_auth

service restart prudynt >/dev/null 2>&1 &

# Redirect back to referer or preview page
referer="${HTTP_REFERER:-/preview.html}"
echo "Status: 302 Found"
echo "Location: $referer"
echo "Connection: close"
echo
