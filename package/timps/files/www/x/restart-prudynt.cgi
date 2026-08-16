#!/bin/sh
# Targeted shellcheck baseline: intentional busybox-ash idioms,
# template artifacts, and runtime-only sources in this file.
# New findings of other codes still fail. Policy: docs/pre-commit-hooks.md
# shellcheck disable=SC1091
# timps replacement for the streamer restart CGI (same name, same URL,
# because the WebUI calls /x/restart-prudynt.cgi; also installed as
# restart-timps.cgi). Restarts the timps streamer service.

# Check authentication
. /var/www/x/auth.sh
require_auth

echo "Content-Type: application/json"
echo "Connection: close"
echo
echo '{"status":"ok","message":"Streamer (timps) restart initiated"}'

/etc/init.d/S95timps restart >/dev/null 2>&1 &
