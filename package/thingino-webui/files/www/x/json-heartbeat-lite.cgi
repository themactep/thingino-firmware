#!/bin/sh

# Ultra-light heartbeat CGI - just reads from daemon-maintained cache

CACHE_FILE="/tmp/heartbeat_cache.json"

printf 'Status: 200 OK\r\n'
printf 'Content-Type: application/json\r\n'
printf 'Cache-Control: no-cache\r\n'
printf 'Pragma: no-cache\r\n'
printf '\r\n'

if [ -f "$CACHE_FILE" ]; then
  cat "$CACHE_FILE"
else
  # Fallback if daemon not running
  printf '{"error":"Heartbeat daemon not running"}'
fi
