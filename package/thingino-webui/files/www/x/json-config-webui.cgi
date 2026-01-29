#!/bin/sh

# Check authentication
. /var/www/x/auth.sh
require_auth

DOMAIN="webui"
CONFIG_FILE="/etc/thingino.json"
TMP_FILE="/tmp/${DOMAIN}-config.$$"
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

write_config() {
  ensure_config
  TMP_FILE=$(mktemp /tmp/${DOMAIN}.XXXXXX)
  echo '{}' >"$TMP_FILE"
  jct "$TMP_FILE" set "$DOMAIN.theme" "$theme" >/dev/null 2>&1
  jct "$TMP_FILE" set "$DOMAIN.paranoid" "$paranoid" >/dev/null 2>&1
  jct "$TMP_FILE" set "$DOMAIN.track_focus" "$track_focus" >/dev/null 2>&1
  jct "$TMP_FILE" set "$DOMAIN.focus_timeout" "$focus_timeout" >/dev/null 2>&1
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

normalize_theme() {
  case "$1" in
    light|dark|auto) printf '%s' "$1" ;;
    ""|null) printf 'auto' ;;
    *) json_error 422 "Unsupported theme" "422 Unprocessable Entity" ;;
  esac
}

normalize_bool() {
  case "$(printf '%s' "$1" | tr 'A-Z' 'a-z')" in
    1|true|yes|on) printf 'true' ;;
    0|false|no|off|""|null) printf 'false' ;;
    *) json_error 422 "Invalid boolean value" "422 Unprocessable Entity" ;;
  esac
}

normalize_int() {
  val="$1"
  min="$2"
  max="$3"

  case "$val" in
    ""|null) printf '0' ;;
    *[!0-9]*) json_error 422 "Invalid integer value" "422 Unprocessable Entity" ;;
    *)
      if [ -n "$min" ] && [ "$val" -lt "$min" ]; then
        printf '%s' "$min"
      elif [ -n "$max" ] && [ "$val" -gt "$max" ]; then
        printf '%s' "$max"
      else
        printf '%s' "$val"
      fi
      ;;
  esac
}

handle_get() {
  send_json "$(read_domain_json)"
}

handle_post() {
  read_body
  new_theme=$(jct "$REQ_FILE" get theme 2>/dev/null)
  new_paranoid=$(jct "$REQ_FILE" get paranoid 2>/dev/null)
  new_track_focus=$(jct "$REQ_FILE" get track_focus 2>/dev/null)
  new_focus_timeout=$(jct "$REQ_FILE" get focus_timeout 2>/dev/null)
  new_password=$(jct "$REQ_FILE" get password 2>/dev/null)

  theme=$(normalize_theme "$new_theme")
  paranoid=$(normalize_bool "$new_paranoid")
  track_focus=$(normalize_bool "$new_track_focus")
  focus_timeout=$(normalize_int "$new_focus_timeout" 0 300)

  write_config

  if [ -n "$new_password" ]; then
    if command -v chpasswd >/dev/null 2>&1; then
      echo "root:$new_password" | chpasswd -c sha512 >/dev/null 2>&1 || json_error 500 "Failed to update password" "500 Internal Server Error"

      # Update session to mark password as no longer default
      if [ -n "$SESSION_ID" ]; then
        session_file="/tmp/sessions/$SESSION_ID"
        if [ -f "$session_file" ]; then
          sed -i "s/^is_default_password=.*/is_default_password=false/" "$session_file"
        fi
      fi
    else
      json_error 500 "Password tool missing" "500 Internal Server Error"
    fi
  fi

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
