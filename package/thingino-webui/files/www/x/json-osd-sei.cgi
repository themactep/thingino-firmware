#!/bin/sh
# SSE stream of OSD SEI data from prudynt.
# Polls /api/v1/osd-sei every 2s and pushes to connected clients.

. /var/www/x/auth.sh
require_auth

STREAM_RETRY_MS="${STREAM_RETRY_MS:-2000}"
POLL_INTERVAL="${POLL_INTERVAL:-2}"

http_200() { printf 'Status: 200 OK\r\n'; }

send_headers() {
  http_200
  cat <<EOF
Content-Type: text/event-stream
Cache-Control: no-cache
Connection: keep-alive
Pragma: no-cache
Expires: 0

EOF
}

stream_data() {
  printf 'retry: %s\n\n' "$STREAM_RETRY_MS" || exit 0
  while true; do
    data=$(curl -s --max-time 3 http://localhost:8080/api/v1/osd-sei 2>/dev/null)
    if [ -n "$data" ]; then
      printf 'data: %s\n\n' "$data" || exit 0
    fi
    sleep "$POLL_INTERVAL" || exit 0
  done
}

trap 'exit 0' INT TERM PIPE HUP
send_headers
stream_data
