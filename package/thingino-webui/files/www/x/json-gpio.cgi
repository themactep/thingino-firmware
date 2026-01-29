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
  printf 'Cache-Control: no-store\r\n'
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

# @params: n - name, s - state
if [ "$REQUEST_METHOD" = "POST" ]; then
  if [ -n "$CONTENT_LENGTH" ] && [ "$CONTENT_LENGTH" -gt 0 ]; then
    CONTENT=$(dd bs=1 count="$CONTENT_LENGTH" 2>/dev/null)
    eval $(echo "$CONTENT" | sed "s/&/;/g")
  fi
else
  eval $(echo "$QUERY_STRING" | sed "s/&/;/g")
fi

[ -z "$n" ] && json_error "Required parameter 'n' is not set"

# Read GPIO pin from configuration file using jct (faster than grep)
pin=$(jct /etc/thingino.json get gpio."$n".pin 2>/dev/null || jct /etc/thingino.json get gpio."$n" 2>/dev/null)
[ -z "$pin" ] && json_error "GPIO '$n' is not configured"

case "$s" in
  0) state=0; gpio set "$pin" "$state" ;;
  1) state=1; gpio set "$pin" "$state" ;;
  *) state='"toggled"'; gpio toggle "$pin" ;;
esac

# Return immediately without verification
printf 'Status: 200 OK\r\nContent-Type: application/json\r\nCache-Control: no-store\r\n\r\n{"pin":"%s","status":%s}\n' "$pin" "$state"
