#!/bin/sh
# shellcheck disable=SC2039
# Day/night control — writes to /etc/thingino.json (daynightd's config)
# and notifies daynightd via SIGHUP on changes.

. /var/www/x/auth.sh
require_auth

http_200()  { printf 'Status: 200 OK\r\n'; }
http_400()  { printf 'Status: 400 Bad Request\r\n'; }
http_412()  { printf 'Status: 412 Precondition Failed\r\n'; }

json_header() {
  printf 'Content-Type: application/json\r\n'
  printf 'Pragma: no-cache\r\n'
  printf 'Expires: %s\r\n' "$(TZ=GMT0 date +'%a, %d %b %Y %T %Z')"
  printf 'Etag: "%s"\r\n' "$(cat /proc/sys/kernel/random/uuid)"
  printf 'Connection: close\r\n'
  printf '\r\n'
}

json_error() {
  http_412; json_header
  printf '{"error":{"code":412,"message":"%s"}}\n' "$1"
  exit 0
}

json_ok() {
  http_200; json_header
  if [ "{" = "${1:0:1}" ]; then
    printf '{"code":200,"result":"success","message":%s}\n' "$1"
  else
    printf '{"code":200,"result":"success","message":"%s"}\n' "$1"
  fi
  exit 0
}

bad_request() {
  http_400; echo; echo "$1"; exit 1
}

daynightd_reload() {
  if [ -f /run/daynightd.pid ]; then
    kill -HUP "$(cat /run/daynightd.pid)" 2>/dev/null || true
  fi
}

CONFIG="${THINGINO_CONFIG:-/etc/thingino.json}"

# Read POST data
read -r POST_DATA

cmd=$(printf '%s' "$POST_DATA" | awk -F'"' '/"cmd"/{for(i=1;i<=NF;i++){if($i=="cmd"){print $(i+2); exit}}}')
val=$(printf '%s' "$POST_DATA" | sed -n 's/.*"val"[[:space:]]*:[[:space:]]*"\{0,1\}\([^",}]*\).*/\1/p')

[ -z "$cmd" ] && bad_request "missing required parameter cmd"
[ -z "$val" ] && bad_request "missing required parameter val"

case "$cmd" in
  auto)
    case "$val" in
      1 | true | on)
        # Enable photosensing, clear force mode
        jct "$CONFIG" set daynight.enabled true  >/dev/null 2>&1
        jct "$CONFIG" set daynight.force_mode "" >/dev/null 2>&1
        daynightd_reload
        ;;
      0 | false | off)
        # Disable photosensing, force day mode
        jct "$CONFIG" set daynight.enabled false  >/dev/null 2>&1
        jct "$CONFIG" set daynight.force_mode day >/dev/null 2>&1
        daynightd_reload
        ;;
    esac
    ;;
  color)
    # Direct ISP color mode toggle — prudynt still handles this
    echo "{\"image\":{\"running_mode\": $val}}" | prudyntctl json - >/dev/null 2>&1
    ;;
  daynight)
    # Direct day/night force — disable photosensing, set mode
    jct "$CONFIG" set daynight.enabled false        >/dev/null 2>&1
    jct "$CONFIG" set daynight.force_mode "$val"    >/dev/null 2>&1
    /sbin/daynight "$val" >/dev/null 2>&1
    daynightd_reload
    ;;
  ir850 | ir940 | white)
    jct "$CONFIG" set daynight.enabled false  >/dev/null 2>&1
    jct "$CONFIG" set daynight.force_mode night >/dev/null 2>&1
    daynightd_reload
    light $cmd $val
    ;;
  ircut)
    jct "$CONFIG" set daynight.enabled false  >/dev/null 2>&1
    ircut $val >/dev/null
    daynightd_reload
    ;;
esac

json_ok
