#!/bin/sh

. /var/www/x/auth.sh
require_auth

DOMAIN="mqtt_sub"
CONFIG_FILE="/etc/thingino.json"
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
    -e "s/\r/\\\\r/g" \
    -e "s/\n/\\\\n/g"
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

strip_json_string() {
  case "$1" in
    ""|null)
      printf ''
      ;;
    *)
      printf '%s' "$1" | sed -e 's/^"//' -e 's/"$//' -e 's/^\\"//' -e 's/\\"$//'
      ;;
  esac
}

normalize_bool() {
  case "$(printf '%s' "$1" | tr 'A-Z' 'a-z')" in
    1|true|yes|on) printf 'true' ;;
    0|false|no|off|""|null) printf 'false' ;;
    *) json_error 422 "Invalid boolean value" "422 Unprocessable Entity" ;;
  esac
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
    ""|null) data='{}' ;;
  esac
  printf '%s' "$data"
}

read_body() {
  REQ_FILE=$(mktemp /tmp/${DOMAIN}-req.XXXXXX)
  if [ -n "$CONTENT_LENGTH" ]; then
    dd bs=1 count="$CONTENT_LENGTH" 2>/dev/null >"$REQ_FILE"
  else
    cat >"$REQ_FILE"
  fi
}

handle_get() {
  send_json "$(read_domain_json)"
}

handle_post() {
  read_body

  new_enabled=$(jct "$REQ_FILE" get enabled 2>/dev/null)
  new_host=$(jct "$REQ_FILE" get host 2>/dev/null)
  new_port=$(jct "$REQ_FILE" get port 2>/dev/null)
  new_username=$(jct "$REQ_FILE" get username 2>/dev/null)
  new_password=$(jct "$REQ_FILE" get password 2>/dev/null)
  new_use_ssl=$(jct "$REQ_FILE" get use_ssl 2>/dev/null)
  new_subscriptions=$(jct "$REQ_FILE" get subscriptions 2>/dev/null)

  enabled=$(normalize_bool "$new_enabled")
  host=$(strip_json_string "$new_host")
  port=$(strip_json_string "$new_port")
  username=$(strip_json_string "$new_username")
  password=$(strip_json_string "$new_password")
  use_ssl=$(normalize_bool "$new_use_ssl")

  [ -n "$port" ] || port="1883"

  if [ "$enabled" = "true" ] && [ -z "$host" ]; then
    json_error 422 "Broker address cannot be empty when service is enabled" "422 Unprocessable Entity"
  fi

  # Build the mqtt_sub object from validated fields, preserving subscriptions array as-is
  TMP_FILE=$(mktemp /tmp/${DOMAIN}.XXXXXX)
  ensure_config

  # Write a wrapper JSON with the full mqtt_sub object
  cat >"$TMP_FILE" <<EOF
{
  "mqtt_sub": {
    "enabled": $enabled,
    "host": "$(json_escape "$host")",
    "port": $port,
    "username": "$(json_escape "$username")",
    "password": "$(json_escape "$password")",
    "use_ssl": $use_ssl,
    "subscriptions": ${new_subscriptions:-[]}
  }
}
EOF

  jct "$CONFIG_FILE" import "$TMP_FILE" >/dev/null 2>&1

  send_json '{"status":"ok"}'
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
