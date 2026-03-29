#!/bin/sh

# Optimized SSE heartbeat - streams from daemon-maintained cache

# Check authentication
. /var/www/x/auth.sh
require_auth

CACHE_FILE="/tmp/heartbeat_cache.json"
HEARTBEAT_INTERVAL="${HEARTBEAT_INTERVAL:-5}"
HEARTBEAT_RETRY_MS=$((HEARTBEAT_INTERVAL * 1000))

read_cache_line() {
  local line

  if IFS= read -r line < "$1" || [ -n "$line" ]; then
    printf '%s\n' "$line"
    return 0
  fi

  return 1
}

http_200() {
  printf 'Status: 200 OK\r\n'
}

send_headers() {
  http_200
  cat <<EOF
Content-Type: text/event-stream
Cache-Control: no-cache

EOF
}

stream_heartbeat() {
  while true; do
    printf 'retry: %d\n' "$HEARTBEAT_RETRY_MS" || exit 0

    # Just read from cache file - daemon updates it
    if [ -r "$CACHE_FILE" ]; then
      cache_line=$(read_cache_line "$CACHE_FILE") || exit 0
      printf 'data: %s\n\n' "$cache_line" || exit 0
    else
      # Fallback if daemon not running
      printf 'data: {"error":"Heartbeat daemon not running"}\n\n' || exit 0
    fi

    sleep "$HEARTBEAT_INTERVAL" || exit 0
  done
}

trap 'exit 0' INT TERM PIPE HUP
send_headers
stream_heartbeat
