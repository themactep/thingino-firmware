#!/bin/sh

DOMAIN="admin"
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
    -e "s/\r/\\r/g" \
    -e "s/\n/\\n/g"
}

send_json() {
  payload="$1"
  status="${2:-200 OK}"
  echo "HTTP/1.1 200 OK
Connection: Close
Content-Length: ${#payload}
Status: $status
Content-Type: application/json
Cache-Control: no-store
Pragma: no-cache

$1
"
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

ensure_default_name() {
  ensure_config
  local current
  current=$(jct "$CONFIG_FILE" get "$DOMAIN.name" 2>/dev/null)
  if [ -z "$current" ] || [ "$current" = "null" ]; then
    jct "$CONFIG_FILE" set "$DOMAIN.name" "Thingino Camera Admin" >/dev/null 2>&1
  fi
}

write_config() {
  ensure_config
  TMP_FILE=$(mktemp /tmp/${DOMAIN}.XXXXXX)
  echo '{}' >"$TMP_FILE"
  jct "$TMP_FILE" set "$DOMAIN.name" "$name" >/dev/null 2>&1
  jct "$TMP_FILE" set "$DOMAIN.email" "$email" >/dev/null 2>&1
  jct "$TMP_FILE" set "$DOMAIN.telegram" "$telegram" >/dev/null 2>&1
  jct "$TMP_FILE" set "$DOMAIN.discord" "$discord" >/dev/null 2>&1
  jct "$CONFIG_FILE" import "$TMP_FILE" >/dev/null 2>&1
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
  ensure_default_name
  send_json "$(read_domain_json)"
}

add_at_prefix() {
  value="$1"
  if [ -n "$value" ] && [ "${value#@}" = "$value" ]; then
    printf '@%s' "$value"
  else
    printf '%s' "$value"
  fi
}

handle_post() {
  read_body
      name=$(jct "$REQ_FILE" get name 2>/dev/null)
     email=$(jct "$REQ_FILE" get email 2>/dev/null)
  telegram=$(jct "$REQ_FILE" get telegram 2>/dev/null)
   discord=$(jct "$REQ_FILE" get discord 2>/dev/null)

  [ -n "$name" ] || name="Thingino Camera Admin"

  telegram=$(add_at_prefix "$telegram")
   discord=$(add_at_prefix "$discord")

  write_config

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
