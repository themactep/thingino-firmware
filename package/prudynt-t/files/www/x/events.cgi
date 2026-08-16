#!/bin/sh
# Targeted shellcheck baseline: intentional busybox-ash idioms,
# template artifacts, and runtime-only sources in this file.
# New findings of other codes still fail. Policy: docs/pre-commit-hooks.md
# shellcheck disable=SC1091
# BusyBox httpd CGI for server-sent events (SSE)

# Check authentication
. /var/www/x/auth.sh
require_auth

printf "Cache-Control: no-cache\r\n"
printf "Content-Type: text/event-stream\r\n"
printf "\r\n"

# Stream prudynt events, converting lines to SSE frames
prudyntctl events | sed -u 's/^/data: /' | while IFS= read -r line; do
	echo "$line"
	echo
done
