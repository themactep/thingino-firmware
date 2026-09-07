#!/bin/sh
# shellcheck disable=SC1091

# Slow heartbeat: one-shot JSON of the cached payload produced by
# S99heartbeat.

. /var/www/x/auth.sh
require_auth

CACHE_FILE="/run/thingino/heartbeat.json"

printf 'Content-Type: application/json\r\n'
printf 'Cache-Control: no-cache\r\n'
printf 'Connection: close\r\n\r\n'

if [ -r "$CACHE_FILE" ]; then
	cat "$CACHE_FILE"
else
	printf '{"error":"Heartbeat daemon not running"}'
fi
