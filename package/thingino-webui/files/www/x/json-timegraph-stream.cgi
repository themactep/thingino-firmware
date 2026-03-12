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
  printf 'Connection: close\r\n'
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

STREAM_RETRY_MS="${STREAM_RETRY_MS:-2000}"

send_headers() {
  http_200
  cat <<EOF
Content-Type: text/event-stream
Cache-Control: no-cache

EOF
}

stream_data() {
  printf 'retry: %s\n\n' "$STREAM_RETRY_MS" || exit 0

  if ! command -v prudyntctl >/dev/null 2>&1; then
    printf 'data: {"error":"prudyntctl not found"}\n\n' || exit 0
    exit 0
  fi

  prudyntctl events 2>/dev/null | while IFS= read -r line; do
    [ -z "$line" ] && continue
    printf 'data: %s\n\n' "$line" || exit 0
  done
}

trap 'exit 0' INT TERM PIPE HUP
send_headers
stream_data
