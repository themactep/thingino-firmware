#!/bin/sh
# Restart the raptor streamer stack.

# shellcheck disable=SC1091  # auth.sh is installed on the camera, not in the build tree
. /var/www/x/auth.sh
require_auth

printf 'Status: 200 OK\r\n'
printf 'Content-Type: application/json\r\n'
printf 'Cache-Control: no-store\r\n'
printf 'Connection: close\r\n'
printf '\r\n'

if [ -x /etc/init.d/S31raptor ]; then
	/etc/init.d/S31raptor restart >/dev/null 2>&1
elif command -v agentctl >/dev/null 2>&1; then
	agentctl restart-streamer >/dev/null 2>&1
else
	printf '{"error":{"message":"raptor restart unavailable"}}\n'
	exit 0
fi

printf '{"status":"ok"}\n'
