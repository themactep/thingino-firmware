#!/bin/sh
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

[ -n "$QUERY_STRING" ] && eval $(echo "$QUERY_STRING" | sed "s/&/;/g")

[ -z "$state" ] && json_error "Missing mandatory parameter: state"

[ -z "$iface" ] && iface="wg0"

is_wg_up() {
  ip link show $iface 2>/dev/null | grep -q UP
}

wg_status() {
  is_wg_up && echo -n 1 || echo -n 0
}

if [ "1" = "$state" ] || [ "true" = "$state" ] ; then
  is_wg_up || service start wireguard
else
  is_wg_up && service stop wireguard
fi

json_ok "{\"status\":$(wg_status),\"message\":\"WireGuard is $(is_wg_up && echo 'up' || echo 'down')\"}"
