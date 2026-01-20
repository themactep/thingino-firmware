#!/bin/sh

. /usr/share/common

DOMAIN="gpio"
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

read_body() {
  REQ_FILE=$(mktemp /tmp/${DOMAIN}-req.XXXXXX)
  if [ -n "$CONTENT_LENGTH" ]; then
    dd bs=1 count="$CONTENT_LENGTH" 2>/dev/null >"$REQ_FILE"
  else
    cat >"$REQ_FILE"
  fi
}

handle_get() {
  gpio_json=$(jct "$CONFIG_FILE" get gpio 2>/dev/null || echo '{}')
  pwm_pins=$(pwm-ctrl -l 2>/dev/null | grep '^GPIO' | awk '{print $2}' | tr '\n' ',' | sed 's/,$//')
  
  cat <<EOF
{
  "gpio": $gpio_json,
  "pwm_pins": "$(json_escape "$pwm_pins")"
}
EOF
}

normalize_bool() {
  case "$(printf '%s' "$1" | tr 'A-Z' 'a-z')" in
    1|true|yes|on) printf 'true' ;;
    *) printf 'false' ;;
  esac
}

save_gpio_pin() {
  local name="$1"
  local pin=$(jct "$REQ_FILE" get "${name}.pin" 2>/dev/null)
  local inv=$(normalize_bool "$(jct "$REQ_FILE" get "${name}.inv" 2>/dev/null)")
  local lit=$(normalize_bool "$(jct "$REQ_FILE" get "${name}.lit" 2>/dev/null)")
  local ch=$(jct "$REQ_FILE" get "${name}.ch" 2>/dev/null)
  local lvl=$(jct "$REQ_FILE" get "${name}.lvl" 2>/dev/null)
  
  [ -z "$pin" ] && return
  
  jct "$TMP_FILE" set "$DOMAIN.$name.pin" "$pin" >/dev/null 2>&1
  jct "$TMP_FILE" set "$DOMAIN.$name.active_low" "$inv" >/dev/null 2>&1
  jct "$TMP_FILE" set "$DOMAIN.$name.active_on_boot" "$lit" >/dev/null 2>&1
  [ -n "$ch" ] && jct "$TMP_FILE" set "$DOMAIN.$name.pwm_channel" "$ch" >/dev/null 2>&1
  [ -n "$lvl" ] && jct "$TMP_FILE" set "$DOMAIN.$name.pwm_level" "$lvl" >/dev/null 2>&1
}

handle_post() {
  read_body
  ensure_config
  
  TMP_FILE=$(mktemp /tmp/${DOMAIN}.XXXXXX)
  echo '{}' >"$TMP_FILE"
  
  save_gpio_pin "led_r"
  save_gpio_pin "led_g"
  save_gpio_pin "led_b"
  save_gpio_pin "led_y"
  save_gpio_pin "led_o"
  save_gpio_pin "led_w"
  save_gpio_pin "ir850"
  save_gpio_pin "ir940"
  save_gpio_pin "white"
  
  ircut_pin1=$(jct "$REQ_FILE" get "ircut_pin1" 2>/dev/null)
  ircut_pin2=$(jct "$REQ_FILE" get "ircut_pin2" 2>/dev/null)
  if [ -n "$ircut_pin1" ] && [ -n "$ircut_pin2" ]; then
    jct "$TMP_FILE" set "$DOMAIN.ircut" "$ircut_pin1 $ircut_pin2" >/dev/null 2>&1
  fi
  
  jct "$CONFIG_FILE" import "$TMP_FILE" >/dev/null 2>&1
  
  send_json '{"status":"ok","message":"GPIO configuration saved"}'
}

case "$REQUEST_METHOD" in
  GET|"")
    send_json "$(handle_get)"
    ;;
  POST)
    handle_post
    ;;
  *)
    json_error 405 "Method not allowed" "405 Method Not Allowed"
    ;;
esac
