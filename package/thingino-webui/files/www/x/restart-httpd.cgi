#!/bin/sh
# Targeted shellcheck baseline: intentional busybox-ash idioms,
# template artifacts, and runtime-only sources in this file.
# New findings of other codes still fail. Policy: docs/pre-commit-hooks.md
# shellcheck disable=SC1091

# Check authentication
. /var/www/x/auth.sh
require_auth

printf "Content-Type: application/json\r\n"
printf "Cache-Control: no-store\r\n"
printf "Connection: close\r\n"
printf "\r\n"

# Restart httpd service
/etc/init.d/S90httpd restart >/dev/null 2>&1 &

printf '{"status":"ok"}\n'
exit 0
