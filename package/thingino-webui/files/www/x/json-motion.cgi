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


[ -n "$QUERY_STRING" ] && eval $(echo "$QUERY_STRING" | sed "s/&/;/g")

case "$target" in
  enabled)
    case "$state" in
      true | false)
        jct /etc/prudynt.json set "motion.$target" $state
        json_ok "{\"target\":\"$target\",\"status\":$state}"
        ;;
      *)
        json_error "state missing"
        ;;
    esac
    ;;
  send2email | send2ftp | send2gphotos | send2mqtt | send2ntfy | send2storage | send2telegram | send2webhook)
    case "$state" in
      true | false)
        jct /etc/prudynt.json set "motion.$target" $state
        json_ok "{\"target\":\"$target\",\"status\":$state}"
        ;;
      *)
        json_error "state missing"
        ;;
    esac
    ;;
  sensitivity | cooldown_time)
      jct /etc/prudynt.json set "motion.$target" $state
      json_ok "{\"target\":\"$target\",\"state\":$state}"
    ;;
  *)
    json_error "target missing"
    ;;
esac
