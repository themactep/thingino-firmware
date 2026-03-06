#!/bin/sh
# Read/write daynight.sun config directly from /etc/prudynt.json via jct.
# Bypasses prudynt API which does not know about these fields.

. /var/www/x/auth.sh
require_auth

CONFIG_FILE="/etc/prudynt.json"
DOMAIN="daynight.sun"
REQ_FILE=""

cleanup() {
  [ -n "$REQ_FILE" ] && rm -f "$REQ_FILE"
}
trap cleanup EXIT

send_json() {
  printf 'Status: 200 OK\r\nContent-Type: application/json\r\nCache-Control: no-store\r\nPragma: no-cache\r\n\r\n%s\n' "$1"
  exit 0
}

json_error() {
  printf 'Status: %s\r\nContent-Type: application/json\r\n\r\n{"error":"%s"}\n' "${2:-400 Bad Request}" "$1"
  exit 0
}

strip_quotes() {
  printf '%s' "$1" | sed -e 's/^"//' -e 's/"$//'
}

handle_get() {
  data=$(jct "$CONFIG_FILE" get "$DOMAIN" 2>/dev/null)
  case "$data" in
    ""|null) data='{}' ;;
  esac
  send_json "{\"sun\":$data}"
}

handle_post() {
  REQ_FILE=$(mktemp /tmp/daynight-sun-req.XXXXXX)
  if [ -n "$CONTENT_LENGTH" ]; then
    dd bs=1 count="$CONTENT_LENGTH" 2>/dev/null >"$REQ_FILE"
  else
    cat >"$REQ_FILE"
  fi

  [ -s "$REQ_FILE" ] || json_error "Empty payload" "400 Bad Request"

  enabled=$(jct "$REQ_FILE" get sun.enabled 2>/dev/null)
  latitude=$(strip_quotes "$(jct "$REQ_FILE" get sun.latitude 2>/dev/null)")
  longitude=$(strip_quotes "$(jct "$REQ_FILE" get sun.longitude 2>/dev/null)")
  sunrise_offset=$(jct "$REQ_FILE" get sun.sunrise_offset 2>/dev/null)
  sunset_offset=$(jct "$REQ_FILE" get sun.sunset_offset 2>/dev/null)

  case "$enabled" in true|false) ;; *) enabled="false" ;; esac

  TMP_FILE=$(mktemp /tmp/daynight-sun-write.XXXXXX)
  echo '{}' >"$TMP_FILE"
  jct "$TMP_FILE" set "$DOMAIN.enabled"        "$enabled"        >/dev/null 2>&1
  jct "$TMP_FILE" set "$DOMAIN.latitude"       "$latitude"       >/dev/null 2>&1
  jct "$TMP_FILE" set "$DOMAIN.longitude"      "$longitude"      >/dev/null 2>&1
  jct "$TMP_FILE" set "$DOMAIN.sunrise_offset" "$sunrise_offset" >/dev/null 2>&1
  jct "$TMP_FILE" set "$DOMAIN.sunset_offset"  "$sunset_offset"  >/dev/null 2>&1

  if ! jct "$CONFIG_FILE" import "$TMP_FILE" >/dev/null 2>&1; then
    rm -f "$TMP_FILE"
    json_error "Failed to save config" "500 Internal Server Error"
  fi
  rm -f "$TMP_FILE"

  send_json '{"status":"ok"}'
}

case "$REQUEST_METHOD" in
  GET|"") handle_get ;;
  POST)   handle_post ;;
  *)      json_error "Method not allowed" "405 Method Not Allowed" ;;
esac
