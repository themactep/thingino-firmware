#!/bin/sh

# Check authentication
. /var/www/x/auth.sh
require_auth

motors_domain="motors"
motors_config_file="/etc/motors.json"

json_escape() {
  printf '%s' "$1" | sed \
    -e 's/\\/\\\\/g' \
    -e 's/"/\\"/g' \
    -e "s/\r/\\r/g" \
    -e "s/\n/\\n/g"
}

read_post_data() {
  if [ -n "$CONTENT_LENGTH" ] && [ "$CONTENT_LENGTH" -gt 0 ]; then
    body=$(dd bs=1 count="$CONTENT_LENGTH" 2>/dev/null)
    eval "$(printf '%s' "$body" | awk -F'&' '{
      for (i=1; i<=NF; i++) {
        split($i, kv, "=")
        key = kv[1]
        value = kv[2]
        gsub(/\+/, " ", value)
        gsub(/%([0-9A-Fa-f]{2})/, "\\x\\1", value)
        printf "POST_%s=\"%s\"\n", key, value
      }
    }')"
  fi
}

http_200() {
  printf 'Status: 200 OK\r\n'
}

http_412() {
  printf 'Status: 412 Precondition Failed\r\n'
}

json_header() {
  printf 'Content-Type: application/json\r\n'
  printf 'Cache-Control: no-store\r\n'
  printf 'Pragma: no-cache\r\n'
  printf 'Expires: %s\r\n' "$(TZ=GMT0 date +'%a, %d %b %Y %T %Z')"
  printf 'Etag: "%s"\r\n' "$(cat /proc/sys/kernel/random/uuid)"
  printf '\r\n'
}

json_error() {
  http_412
  json_header
  printf '{"error":{"code":412,"message":"%s"}}\n' "$(json_escape "$1")"
  exit 0
}

json_ok() {
  http_200
  json_header
  if [ "{" = "${1:0:1}" ]; then
    printf '{"code":200,"result":"success","message":%s}\n' "$1"
  else
    printf '{"code":200,"result":"success","message":"%s"}\n' "$(json_escape "$1")"
  fi
  exit 0
}

motors_set_value() {
  jct "$motors_config_file" set "$motors_domain.$1" "$2" >/dev/null 2>&1
}

motors_get_field() {
  jct "$motors_config_file" get "$motors_domain.$1" 2>/dev/null
}

ensure_config_file() {
  [ -f "$motors_config_file" ] && return
  umask_old=$(umask)
  umask 077
  echo '{}' > "$motors_config_file"
  umask "$umask_old"
}

current_config_payload() {
  local payload
  payload=$(jct "$motors_config_file" get "$motors_domain" 2>/dev/null)
  if [ -z "$payload" ] || [ "$payload" = "null" ]; then
    payload='{}'
  fi
  printf '%s' "$payload"
}

respond_with_config() {
  ensure_config_file
  json_ok "$(current_config_payload)"
}

handle_get() {
  ensure_config_file
  respond_with_config
}

handle_post() {
  ensure_config_file
  read_post_data
  [ "$POST_form" = "motors" ] || json_error "motors-form-missing"

  gpio_pan_1=$POST_gpio_pan_1
  gpio_pan_2=$POST_gpio_pan_2
  gpio_pan_3=$POST_gpio_pan_3
  gpio_pan_4=$POST_gpio_pan_4
  gpio_tilt_1=$POST_gpio_tilt_1
  gpio_tilt_2=$POST_gpio_tilt_2
  gpio_tilt_3=$POST_gpio_tilt_3
  gpio_tilt_4=$POST_gpio_tilt_4
  homing_value=${POST_homing:-false}
  pos_0_x=$POST_pos_0_x
  pos_0_y=$POST_pos_0_y
  speed_pan_value=$POST_speed_pan
  speed_tilt_value=$POST_speed_tilt
  steps_pan_value=$POST_steps_pan
  steps_tilt_value=$POST_steps_tilt

  [ "$homing_value" = "true" ] || homing_value="false"

  is_spi_value=$(motors_get_field is_spi)

  if [ "true" != "$is_spi_value" ]; then
    if [ -z "$gpio_pan_1" ] || [ -z "$gpio_pan_2" ] || [ -z "$gpio_pan_3" ] || [ -z "$gpio_pan_4" ] || \
       [ -z "$gpio_tilt_1" ] || [ -z "$gpio_tilt_2" ] || [ -z "$gpio_tilt_3" ] || [ -z "$gpio_tilt_4" ]; then
      json_error "All motor GPIO pins are required"
    fi
  fi

  if [ "0$steps_pan_value" -le 0 ] || [ "0$steps_tilt_value" -le 0 ]; then
    json_error "Motor max steps must be positive"
  fi

  if [ "true" != "$is_spi_value" ]; then
    motors_set_value gpio_pan "$gpio_pan_1 $gpio_pan_2 $gpio_pan_3 $gpio_pan_4"
    motors_set_value gpio_tilt "$gpio_tilt_1 $gpio_tilt_2 $gpio_tilt_3 $gpio_tilt_4"
  fi

  motors_set_value steps_pan "$steps_pan_value"
  motors_set_value steps_tilt "$steps_tilt_value"
  motors_set_value speed_pan "$speed_pan_value"
  motors_set_value speed_tilt "$speed_tilt_value"
  motors_set_value homing "$homing_value"

  if [ -n "$pos_0_x" ] && [ -n "$pos_0_y" ]; then
    motors_set_value pos_0 "$pos_0_x,$pos_0_y"
  else
    motors_set_value pos_0 ""
  fi

  respond_with_config
}

case "$REQUEST_METHOD" in
  GET)
    handle_get
    ;;
  POST)
    handle_post
    ;;
  *)
    json_error "motors-method-unsupported"
    ;;
esac
