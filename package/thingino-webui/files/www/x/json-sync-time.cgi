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

if [ "true" = "$wlanap_enabled" ]; then
  [ -n "$QUERY_STRING" ] && eval $(echo "$QUERY_STRING" | sed "s/&/;/g")
  now=$(date +%s)
  ys=31557600

  [ -z "$ts" ] && json_error "Missing required parameter 'ts'"
  ts=$(((ts + 999) / 1000))

  [ "$ts" -lt $now ] && json_error "Cannot go back in time: $ts"
  [ "$ts" -gt $((now + ys)) ] && json_error "Time gap is more that a year. It's time to upgrade!"

  date -s "@$ts"
  json_ok "Camera time synchronized from the browser. Time is $(date)"
else
  if ntpd -n -q -N; then
    json_ok "Camera time synchronized with NTP server. Time is $(date)"
  else
    json_error "Synchronization failed!"
  fi
fi

