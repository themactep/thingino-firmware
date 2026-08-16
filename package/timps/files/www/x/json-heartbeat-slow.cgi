#!/bin/sh
# Targeted shellcheck baseline: intentional busybox-ash idioms,
# template artifacts, and runtime-only sources in this file.
# New findings of other codes still fail. Policy: docs/pre-commit-hooks.md
# shellcheck disable=SC1091
# timps replacement for the slow (polled) heartbeat CGI (same name, same URL).
# Same payload as json-heartbeat.cgi, single shot (see timps-heartbeat.sh).

# Check authentication
. /var/www/x/auth.sh
require_auth

. /var/www/x/timps-heartbeat.sh

printf 'Content-Type: application/json\r\n'
printf 'Cache-Control: no-cache\r\n'
printf 'Connection: close\r\n\r\n'

timps_heartbeat_payload
