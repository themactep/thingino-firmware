#!/bin/sh

# Check authentication
. /var/www/x/auth.sh
require_auth

. /usr/share/common

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

read_config() {
  tz_name=""
  tz_data=""
  ntp_server_0=""
  ntp_server_1=""
  ntp_server_2=""
  ntp_server_3=""

  [ -f /etc/timezone ] && tz_name="$(cat /etc/timezone)"
  [ -f /etc/TZ ] && tz_data="$(cat /etc/TZ)"

  if [ -f "$NTP_WORKING_FILE" ]; then
    ntp_server_0="$(sed -n 1p $NTP_WORKING_FILE | cut -d' ' -f2)"
    ntp_server_1="$(sed -n 2p $NTP_WORKING_FILE | cut -d' ' -f2)"
    ntp_server_2="$(sed -n 3p $NTP_WORKING_FILE | cut -d' ' -f2)"
    ntp_server_3="$(sed -n 4p $NTP_WORKING_FILE | cut -d' ' -f2)"
  fi
}

write_config() {
  if [ -n "$tz_data" ]; then
    echo "$tz_data" > /etc/TZ
  fi

  if [ -n "$tz_name" ]; then
    echo "$tz_name" > /etc/timezone
  fi

  tmp_file=$(mktemp)
  [ -n "$ntp_server_0" ] && echo "server $ntp_server_0 iburst" >> "$tmp_file"
  [ -n "$ntp_server_1" ] && echo "server $ntp_server_1 iburst" >> "$tmp_file"
  [ -n "$ntp_server_2" ] && echo "server $ntp_server_2 iburst" >> "$tmp_file"
  [ -n "$ntp_server_3" ] && echo "server $ntp_server_3 iburst" >> "$tmp_file"

  if [ -s "$tmp_file" ]; then
    mv "$tmp_file" "$NTP_DEFAULT_FILE"
    cp "$NTP_DEFAULT_FILE" "$NTP_WORKING_FILE"
    chmod 444 "$NTP_DEFAULT_FILE"
    chmod 444 "$NTP_WORKING_FILE"
  else
    rm -f "$tmp_file"
  fi

  service restart timezone > /dev/null 2>&1
}

read_body() {
  REQ_FILE=$(mktemp /tmp/time-req.XXXXXX)
  if [ -n "$CONTENT_LENGTH" ]; then
    dd bs=1 count="$CONTENT_LENGTH" 2>/dev/null >"$REQ_FILE"
  else
    cat >"$REQ_FILE"
  fi
}

handle_get() {
  read_config

  cat <<EOF
{
  "tz_name": "$(json_escape "$tz_name")",
  "tz_data": "$(json_escape "$tz_data")",
  "ntp_server_0": "$(json_escape "$ntp_server_0")",
  "ntp_server_1": "$(json_escape "$ntp_server_1")",
  "ntp_server_2": "$(json_escape "$ntp_server_2")",
  "ntp_server_3": "$(json_escape "$ntp_server_3")"
}
EOF
}

handle_post() {
  read_body

  action=$(jct "$REQ_FILE" get action 2>/dev/null)

  case "$action" in
    reset)
      if [ -f "/rom$NTP_DEFAULT_FILE" ]; then
        cp -f "/rom$NTP_DEFAULT_FILE" "$NTP_WORKING_FILE"
        send_json '{"status":"ok","message":"NTP configuration reset to defaults"}'
      else
        json_error 404 "Default NTP configuration not found" "404 Not Found"
      fi
      ;;

    set_time)
      manual_time=$(jct "$REQ_FILE" get time 2>/dev/null)
      if [ -z "$manual_time" ]; then
        json_error 422 "Missing time parameter" "422 Unprocessable Entity"
      fi
      date -s "$manual_time" >/dev/null 2>&1
      if [ $? -eq 0 ]; then
        send_json "{\"status\":\"ok\",\"message\":\"Time set to $(date)\"}"
      else
        json_error 500 "Failed to set time" "500 Internal Server Error"
      fi
      ;;

    update)
      tz_name=$(jct "$REQ_FILE" get tz_name 2>/dev/null)
      tz_data=$(jct "$REQ_FILE" get tz_data 2>/dev/null)
      ntp_server_0=$(jct "$REQ_FILE" get ntp_server_0 2>/dev/null)
      ntp_server_1=$(jct "$REQ_FILE" get ntp_server_1 2>/dev/null)
      ntp_server_2=$(jct "$REQ_FILE" get ntp_server_2 2>/dev/null)
      ntp_server_3=$(jct "$REQ_FILE" get ntp_server_3 2>/dev/null)

      if [ -z "$tz_name" ]; then
        json_error 422 "Timezone name cannot be empty" "422 Unprocessable Entity"
      fi

      if [ -z "$tz_data" ]; then
        json_error 422 "Timezone value cannot be empty" "422 Unprocessable Entity"
      fi

      write_config
      send_json '{"status":"ok","message":"Time configuration updated"}'
      ;;

    *)
      json_error 400 "Unknown action: $action" "400 Bad Request"
      ;;
  esac
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
