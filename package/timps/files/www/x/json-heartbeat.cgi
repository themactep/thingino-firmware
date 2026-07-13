#!/bin/sh
# timps replacement for the SSE heartbeat CGI (same name, same URL).
# The stock version proxies the thingino agent, which has no timps backend
# and reports unknown/false for every control-bar field (resetting the
# day/night/auto and Mic buttons). This one builds the payload from timps's
# GET /control and the thingino GPIO tools (see timps-heartbeat.sh).

# Check authentication
. /var/www/x/auth.sh
require_auth

. /var/www/x/timps-heartbeat.sh

HEARTBEAT_INTERVAL="${HEARTBEAT_INTERVAL:-5}"
HEARTBEAT_RETRY_MS=$((HEARTBEAT_INTERVAL * 1000))

http_200() { printf 'Status: 200 OK\r\n'; }

send_headers() {
	http_200
	printf 'Content-Type: text/event-stream\r\n'
	printf 'Cache-Control: no-cache\r\n\r\n'
}

trap 'exit 0' INT TERM PIPE HUP
send_headers

while true; do
	printf 'retry: %d\n' "$HEARTBEAT_RETRY_MS" || exit 0
	data=$(timps_heartbeat_payload)
	if [ -n "$data" ]; then
		printf 'data: %s\n\n' "$data" || exit 0
	else
		printf 'data: {"error":"timps heartbeat unavailable"}\n\n' || exit 0
	fi
	sleep "$HEARTBEAT_INTERVAL" || exit 0
done
