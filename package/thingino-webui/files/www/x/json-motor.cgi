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

[ -z "$x" ] && x=0
[ -z "$y" ] && y=0
[ -z "$d" ] && d="g"

emit_status() {
  local payload
  if ! payload=$(motors -j 2>/dev/null); then
    json_error "motors-status-failed"
  fi
  json_ok "$payload"
}

case "$d" in
  g) motors -d g -x "$x" -y "$y" >/dev/null ;;
  r) motors -r >/dev/null ;;
  h) motors -d h -x "$x" -y "$y" >/dev/null ;;
  s) motors -d s >/dev/null ;;
  b) motors -d b >/dev/null ;;
  i)
    payload=$(motors -i 2>/dev/null) || json_error "motors-initial-failed"
    json_ok "$payload"
    ;;
  j)
    payload=$(motors -j 2>/dev/null) || json_error "motors-status-failed"
    json_ok "$payload"
    ;;
  *)
    json_error "motors-command-unsupported"
    ;;
esac

emit_status
