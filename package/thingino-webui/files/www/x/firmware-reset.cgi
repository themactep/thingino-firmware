#!/bin/sh

# Check authentication
. /var/www/x/auth.sh
require_auth

REQ_FILE=""

cleanup() {
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

strip_json_string() {
  local value
  case "$1" in
    ""|null)
      printf ''
      ;;
    *)
      value="$1"
      value="${value#\"}"
      value="${value%\"}"
      printf '%s' "$value"
      ;;
  esac
}

read_body() {
  REQ_FILE=$(mktemp /tmp/firmware-reset.XXXXXX)
  if [ -n "$CONTENT_LENGTH" ]; then
    dd bs=1 count="$CONTENT_LENGTH" 2>/dev/null >"$REQ_FILE"
  else
    cat >"$REQ_FILE"
  fi
}

resolve_action() {
  case "$1" in
    wipeoverlay)
      action_label="Wipe overlay"
      action_description="Erase data stored in the overlay partition."
      action_command="flash_eraseall -j /dev/mtd2"
      action_reboot="true"
      ;;
    fullreset)
      action_label="Reset firmware"
      action_description="Restore firmware to factory defaults."
      action_command="firstboot -f"
      action_reboot="true"
      ;;
    *)
      return 1
      ;;
  esac
}

handle_get() {
  send_json '{"actions":[{"id":"wipeoverlay","label":"Wipe overlay","description":"Erase data stored in the overlay partition."},{"id":"fullreset","label":"Reset firmware","description":"Restore firmware to factory defaults."}]}'
}

handle_post() {
  read_body
  action_raw=$(jct "$REQ_FILE" get action 2>/dev/null)
  action=$(strip_json_string "$action_raw")

  [ -n "$action" ] || json_error 422 "Action is required" "422 Unprocessable Entity"

  if ! resolve_action "$action"; then
    json_error 422 "Unknown action: $action" "422 Unprocessable Entity"
  fi

  payload=$(printf '{"action":"%s","label":"%s","description":"%s","command":"%s","reboot":%s}' \
    "$(json_escape "$action")" \
    "$(json_escape "$action_label")" \
    "$(json_escape "$action_description")" \
    "$(json_escape "$action_command")" \
    "$action_reboot")

  send_json "$payload"
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

