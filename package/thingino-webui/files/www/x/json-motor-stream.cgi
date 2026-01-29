#!/bin/sh

# Check authentication
. /var/www/x/auth.sh
require_auth

http_200() {
  printf 'Status: 200 OK\r\n'
}

http_400() {
  printf 'Status: 400 Bad Request\r\n'
}

http_412() {
  printf 'Status: 412 Precondition Failed\r\n'
}

json_header() {
  printf 'Content-Type: application/json\r\n'
  printf 'Pragma: no-cache\r\n'
  printf 'Expires: %s\r\n' "$(TZ=GMT0 date +'%a, %d %b %Y %T %Z')"
  printf 'Etag: "%s"\r\n' "$(cat /proc/sys/kernel/random/uuid)"
  printf '\r\n'
}

json_error() {
  http_412
  json_header
  printf '{"error":{"code":412,"message":"%s"}}
' "$1"
  exit 0
}

json_ok() {
  http_200
  json_header
  if [ "{" = "${1:0:1}" ]; then
    printf '{"code":200,"result":"success","message":%s}
' "$1"
  else
    printf '{"code":200,"result":"success","message":"%s"}
' "$1"
  fi
  exit 0
}


STREAM_INTERVAL_RAW="${MOTOR_STREAM_INTERVAL:-1}"
case "$STREAM_INTERVAL_RAW" in
  ''|*[!0-9]*) STREAM_INTERVAL=1 ;;
  *) STREAM_INTERVAL="$STREAM_INTERVAL_RAW" ;;
esac
STREAM_RETRY_MS=$((STREAM_INTERVAL * 300))

send_headers() {
  http_200
  cat <<EOF
Content-Type: text/event-stream
Cache-Control: no-cache
Connection: keep-alive

EOF
}

emit_single_event() {
  local payload="$1"
  [ -n "$payload" ] || payload='{"error":"motor-stream-empty"}'
  printf 'data: %s\n\n' "$payload"
}

read_motor_payload() {
  local raw
  if ! raw=$(motors -j 2>/dev/null); then
    printf '%s' '{"error":"motors-read-failed"}'
    return
  fi
  raw=$(printf '%s' "$raw" | tr -d '\r' | tr -d '\n')
  if [ -z "$raw" ]; then
    printf '%s' '{"error":"motors-read-empty"}'
  else
    printf '%s' "$raw"
  fi
}

stream_loop() {
  while true; do
    local payload
    payload=$(read_motor_payload)
    printf 'retry: %d\n' "$STREAM_RETRY_MS" || exit 0
    printf 'data: %s\n\n' "$payload" || exit 0
    sleep "$STREAM_INTERVAL" || exit 0
  done
}

if ! command -v motors >/dev/null 2>&1; then
  send_headers
  emit_single_event '{"error":"motors-binary-missing"}'
  exit 0
fi

trap 'exit 0' INT TERM PIPE HUP
send_headers
stream_loop
