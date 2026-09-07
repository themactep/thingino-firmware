#!/bin/sh
# shellcheck disable=SC1091

# SSE heartbeat: relay the cached payload produced by S99heartbeat.

. /var/www/x/auth.sh
require_auth

HEARTBEAT_INTERVAL="${HEARTBEAT_INTERVAL:-5}"
HEARTBEAT_RETRY_MS=$((HEARTBEAT_INTERVAL * 1000))
CACHE_FILE="/run/thingino/heartbeat.json"

printf 'Status: 200 OK\r\n'
printf 'Content-Type: text/event-stream\r\n'
printf 'Cache-Control: no-cache\r\n\r\n'

trap 'exit 0' INT TERM PIPE HUP

while true; do
	printf 'retry: %d\n' "$HEARTBEAT_RETRY_MS" || exit 0
	if [ -r "$CACHE_FILE" ]; then
		printf 'data: ' || exit 0
		cat "$CACHE_FILE" || exit 0
		printf '\n\n' || exit 0
	else
		printf 'data: {"error":"Heartbeat daemon not running"}\n\n' || exit 0
	fi
	sleep "$HEARTBEAT_INTERVAL" || exit 0
done
