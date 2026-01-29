#!/bin/sh

# Check authentication
. /var/www/x/auth.sh
require_auth

printf "Content-Type: application/json\r\n"
printf "Cache-Control: no-store\r\n"
printf "\r\n"

# Restart httpd service
/etc/init.d/S90httpd restart >/dev/null 2>&1 &

printf '{"status":"ok"}\n'
exit 0
