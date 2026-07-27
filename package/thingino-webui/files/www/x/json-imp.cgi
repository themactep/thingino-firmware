#!/bin/sh
# shellcheck disable=SC2039

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

bad_request() {
  http_400
  echo
  echo "$1"
  exit 1
}

# Disable day/night auto so manual light/ircut/color controls stick.
# Prefer agent, then raptor, then prudynt — never require prudyntctl alone.
disable_daynight_auto() {
  if command -v thingino-agentctl >/dev/null 2>&1; then
    tmp=$(mktemp /tmp/imp-daynight.XXXXXX) || return 1
    printf '{"enabled":false}\n' >"$tmp"
    thingino-agentctl set-setting daynight/enabled "$tmp" >/dev/null 2>&1 || true
    rm -f "$tmp"
    return 0
  fi
  if command -v raptorctl >/dev/null 2>&1; then
    # Keep current RIC state if possible; fall back to day.
    mode=$(raptorctl ric status 2>/dev/null | sed -n 's/.*"state"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
    case "$mode" in
      day | night) ;;
      *) mode=day ;;
    esac
    raptorctl ric mode "$mode" >/dev/null 2>&1 || true
    return 0
  fi
  if command -v prudyntctl >/dev/null 2>&1; then
    echo '{"daynight":{"enabled":false}}' | prudyntctl json - >/dev/null 2>&1 || true
  fi
}

# Read POST data
read -r POST_DATA

# Parse JSON (supports quoted or numeric val)
cmd=$(printf '%s' "$POST_DATA" | awk -F'"' '/"cmd"/{for(i=1;i<=NF;i++){if($i=="cmd"){print $(i+2); exit}}}')
val=$(printf '%s' "$POST_DATA" | sed -n 's/.*"val"[[:space:]]*:[[:space:]]*"\{0,1\}\([^",}]*\).*/\1/p')

[ -z "$cmd" ] && bad_request "missing required parameter cmd"
[ -z "$val" ] && bad_request "missing required parameter val"

case "$cmd" in
  auto)
    if command -v thingino-agentctl >/dev/null 2>&1; then
      thingino-agentctl daynight auto >/dev/null 2>&1 || json_error "daynight auto failed"
    elif command -v prudyntctl >/dev/null 2>&1; then
      echo '{"daynight":{"enabled":true}}' | prudyntctl json - >/dev/null 2>&1
    elif command -v raptorctl >/dev/null 2>&1; then
      raptorctl ric mode auto >/dev/null 2>&1 || json_error "daynight auto failed"
    else
      json_error "no daynight backend available"
    fi
    ;;
  color)
    disable_daynight_auto
    if command -v prudyntctl >/dev/null 2>&1; then
      echo "{\"daynight\":{\"enabled\":false},\"image\":{\"running_mode\": $val}}" | prudyntctl json - >/dev/null 2>&1
    elif command -v raptorctl >/dev/null 2>&1; then
      # Raptor has no direct running_mode leaf; treat as best-effort no-op success
      # after disabling auto so other controls remain usable.
      true
    else
      json_error "color mode backend unavailable"
    fi
    ;;
  daynight)
    if command -v thingino-agentctl >/dev/null 2>&1; then
      thingino-agentctl daynight "$val" >/dev/null 2>&1 || json_error "daynight failed"
    elif command -v prudyntctl >/dev/null 2>&1; then
      echo "{\"daynight\":{\"enabled\":false,\"force_mode\":\"$val\"}}" | prudyntctl json - >/dev/null 2>&1
    elif command -v raptorctl >/dev/null 2>&1; then
      raptorctl ric mode "$val" >/dev/null 2>&1 || json_error "daynight failed"
    else
      json_error "no daynight backend available"
    fi
    ;;
  ir850 | ir940 | white)
    disable_daynight_auto
    light $cmd $val
    ;;
  ircut)
    disable_daynight_auto
    ircut $val >/dev/null
    ;;
esac

# All state data is provided by heartbeat, no need to build payload here
json_ok
