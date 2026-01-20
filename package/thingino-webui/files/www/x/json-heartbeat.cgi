#!/bin/sh

# Optimized SSE heartbeat - streams from daemon-maintained cache

CACHE_FILE="/tmp/heartbeat_cache.json"
HEARTBEAT_INTERVAL="${HEARTBEAT_INTERVAL:-1}"
HEARTBEAT_RETRY_MS=$((HEARTBEAT_INTERVAL * 1000))

http_200() {
  printf 'Status: 200 OK\r\n'
}

send_headers() {
  http_200
  cat <<EOF
Content-Type: text/event-stream
Cache-Control: no-cache
Connection: keep-alive

EOF
}

stream_heartbeat() {
  while true; do
    printf 'retry: %d\n' "$HEARTBEAT_RETRY_MS" || exit 0
    
    # Just read from cache file - daemon updates it
    if [ -f "$CACHE_FILE" ]; then
      printf 'data: %s\n\n' "$(cat "$CACHE_FILE")" || exit 0
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
