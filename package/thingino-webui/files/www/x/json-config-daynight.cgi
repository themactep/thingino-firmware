#!/bin/sh

# thingino day/night configuration access
# GET  → returns current daynight config from /etc/thingino.json
# POST → updates daynight config in /etc/thingino.json

# Check authentication
. /var/www/x/auth.sh
require_auth

DOMAIN="daynight"
CONFIG_FILE="${THINGINO_CONFIG:-/etc/thingino.json}"
TMP_FILE=""
REQ_FILE=""

cleanup() {
  [ -n "$TMP_FILE" ] && rm -f "$TMP_FILE"
  [ -n "$REQ_FILE" ] && rm -f "$REQ_FILE"
}
trap cleanup EXIT

json_escape() {
  printf '%s' "$1" | sed \
    -e 's/\\/\\\\/g' \
    -e 's/"/\\"/g' \
    -e "s/\r/\\r/g" \
    -e "s/\n/\\n/g"
}

send_json() {
  status="${2:-200 OK}"
  printf 'Status: %s\n' "$status"
  cat <<EOF
Content-Type: application/json
Cache-Control: no-store
Pragma: no-cache
Connection: close

$1
EOF
  exit 0
}

json_error() {
  code="${1:-400}"
  message="$2"
  send_json "{\"error\":{\"code\":$code,\"message\":\"$(json_escape "$message")\"}}" "${3:-400 Bad Request}"
}

ensure_config() {
  if [ ! -f "$CONFIG_FILE" ]; then
    umask 077
    echo '{}' >"$CONFIG_FILE"
  fi
}

read_domain_json() {
  ensure_config
  local data
  data=$(jct "$CONFIG_FILE" get "$DOMAIN" 2>/dev/null)
  case "$data" in
    ""|null)
      data='{}'
      ;;
  esac
  printf '%s' "$data"
}

apply_defaults() {
  ensure_config
  local current
  current=$(jct "$CONFIG_FILE" get "$DOMAIN" 2>/dev/null)
  if [ -z "$current" ] || [ "$current" = "null" ]; then
    # Initialize with defaults
    jct "$CONFIG_FILE" set "$DOMAIN.enabled" true >/dev/null 2>&1
    jct "$CONFIG_FILE" set "$DOMAIN.controls.color" true >/dev/null 2>&1
    jct "$CONFIG_FILE" set "$DOMAIN.controls.ircut" true >/dev/null 2>&1
    jct "$CONFIG_FILE" set "$DOMAIN.controls.ir850" true >/dev/null 2>&1
    jct "$CONFIG_FILE" set "$DOMAIN.controls.ir940" true >/dev/null 2>&1
    jct "$CONFIG_FILE" set "$DOMAIN.controls.white" false >/dev/null 2>&1
    jct "$CONFIG_FILE" set "$DOMAIN.total_gain_day_threshold" 300 >/dev/null 2>&1
    jct "$CONFIG_FILE" set "$DOMAIN.total_gain_night_threshold" 3000 >/dev/null 2>&1
    jct "$CONFIG_FILE" set "$DOMAIN.script_path" "/sbin/daynight" >/dev/null 2>&1
    jct "$CONFIG_FILE" set "$DOMAIN.schedule.enabled" false >/dev/null 2>&1
    jct "$CONFIG_FILE" set "$DOMAIN.schedule.start_at" "" >/dev/null 2>&1
    jct "$CONFIG_FILE" set "$DOMAIN.schedule.stop_at" "" >/dev/null 2>&1
    jct "$CONFIG_FILE" set "$DOMAIN.sun.enabled" false >/dev/null 2>&1
    jct "$CONFIG_FILE" set "$DOMAIN.sun.latitude" "" >/dev/null 2>&1
    jct "$CONFIG_FILE" set "$DOMAIN.sun.longitude" "" >/dev/null 2>&1
    jct "$CONFIG_FILE" set "$DOMAIN.sun.sunrise_offset" 0 >/dev/null 2>&1
    jct "$CONFIG_FILE" set "$DOMAIN.sun.sunset_offset" 0 >/dev/null 2>&1
  fi
}

write_daynight() {
  ensure_config
  TMP_FILE=$(mktemp /tmp/thingino-${DOMAIN}.XXXXXX)
  echo '{}' >"$TMP_FILE"

  # Get current daynight config first to preserve unchanged keys
  current_data=$(jct "$CONFIG_FILE" get "$DOMAIN" 2>/dev/null || echo '{}')
  echo "$current_data" | jct "$TMP_FILE" import /dev/stdin >/dev/null 2>&1

  # Apply changes from request
  jct "$TMP_FILE" import "$REQ_FILE" >/dev/null 2>&1

  # Merge back into the main config
  jct "$CONFIG_FILE" import "$TMP_FILE" >/dev/null 2>&1
}

read_body() {
  REQ_FILE=$(mktemp /tmp/thingino-req.XXXXXX)
  if [ -n "$CONTENT_LENGTH" ] && [ "$CONTENT_LENGTH" -gt 0 ]; then
    dd bs=1 count="$CONTENT_LENGTH" 2>/dev/null >"$REQ_FILE"
  else
    cat >"$REQ_FILE"
  fi
}

handle_get() {
  apply_defaults
  send_json "$(read_domain_json)"
}

handle_post() {
  read_body
  write_daynight
  send_json "$(read_domain_json)"
}

case "$REQUEST_METHOD" in
  GET|"")
    handle_get
    ;;
  POST)
    handle_post
    ;;
  *)
    json_error 405 "Method not allowed" "405 Method Not Allowed"
    ;;
esac
