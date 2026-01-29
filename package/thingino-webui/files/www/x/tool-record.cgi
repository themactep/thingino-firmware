#!/bin/sh

# Check authentication
. /var/www/x/auth.sh
require_auth

. /usr/share/common

RECORD_FILENAME_FB="%Y%m%d/%H/%Y%m%dT%H%M%S"

vr_domain="recorder"
vr_config_file="/etc/prudynt.json"
vr_temp_config_file="/tmp/${vr_domain}.json"

tl_domain="timelapse"
tl_config_file="/etc/timelapse.json"
tl_temp_config_file="/tmp/${tl_domain}.json"

request_body=""
MOUNTS_LIST=""

vr_defaults() {
  [ -z "$vr_autostart" ] && vr_autostart="false"
  [ -z "$vr_channel" ] && vr_channel=0
  [ -z "$vr_device_path" ] && vr_device_path="$(hostname)/records"
  [ -z "$vr_filename" ] && vr_filename="$RECORD_FILENAME_FB"
  [ "/" = "${vr_filename: -1}" ] && vr_filename="$RECORD_FILENAME_FB"
  [ -z "$vr_duration" ] && vr_duration=60
  [ -z "$vr_limit" ] && vr_limit=15
}

vr_set_value() {
  [ -f "$vr_temp_config_file" ] || echo '{}' > "$vr_temp_config_file"
  jct "$vr_temp_config_file" set "$vr_domain.$1" "$2" >/dev/null 2>&1
}

vr_get_value() {
  jct "$vr_config_file" get "$vr_domain.$1" 2>/dev/null
}

vr_read_config() {
  [ -f "$vr_config_file" ] || return
  vr_autostart=$(vr_get_value autostart)
  vr_channel=$(vr_get_value channel)
  vr_device_path=$(vr_get_value device_path)
  vr_duration=$(vr_get_value duration)
  vr_filename=$(vr_get_value filename)
  vr_limit=$(vr_get_value limit)
  vr_mount=$(vr_get_value mount)
}

tl_defaults() {
  [ -z "$tl_enabled" ] && tl_enabled="false"
  [ -z "$tl_filepath" ] && tl_filepath="$(hostname)/timelapses"
  [ -z "$tl_filename" ] && tl_filename="%Y%m%d/%Y%m%dT%H%M%S.jpg"
  [ -z "$tl_interval" ] && tl_interval=1
  [ -z "$tl_keep_days" ] && tl_keep_days=7
  [ -z "$tl_preset_enabled" ] && tl_preset_enabled="false"
  [ -z "$tl_ircut" ] && tl_ircut="false"
  [ -z "$tl_ir850" ] && tl_ir850="false"
  [ -z "$tl_ir940" ] && tl_ir940="false"
  [ -z "$tl_white" ] && tl_white="false"
  [ -z "$tl_color" ] && tl_color="false"
}

tl_set_value() {
  [ -f "$tl_temp_config_file" ] || echo '{}' > "$tl_temp_config_file"
  jct "$tl_temp_config_file" set "$tl_domain.$1" "$2" >/dev/null 2>&1
}

tl_get_value() {
  jct "$tl_config_file" get "$tl_domain.$1" 2>/dev/null
}

tl_read_config() {
  [ -f "$tl_config_file" ] || return
  tl_enabled=$(tl_get_value enabled)
  tl_mount=$(tl_get_value mount)
  tl_filepath=$(tl_get_value filepath)
  tl_filename=$(tl_get_value filename)
  tl_interval=$(tl_get_value interval)
  tl_keep_days=$(tl_get_value keep_days)
  tl_preset_enabled=$(tl_get_value preset_enabled)
  tl_ircut=$(tl_get_value ircut)
  tl_ir850=$(tl_get_value ir850)
  tl_ir940=$(tl_get_value ir940)
  tl_white=$(tl_get_value white)
  tl_color=$(tl_get_value color)
}

list_mounts() {
  awk '/cif|fat|nfs|smb/{print $2}' /etc/mtab 2>/dev/null
}

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

bool_to_json() {
  [ "${1}" = "true" ] && printf 'true' || printf 'false'
}

normalize_bool() {
  case "${1}" in
    1|true|TRUE|on|ON|yes|YES) printf 'true' ;;
    *) printf 'false' ;;
  esac
}

is_positive_int() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
  esac
  [ "$1" -gt 0 ] 2>/dev/null
}

is_non_negative_int() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
  esac
  [ "$1" -ge 0 ] 2>/dev/null
}

urldecode() {
  local data="${1//+/ }"
  printf '%b' "${data//%/\\x}"
}

read_request_body() {
  request_body=""
  [ "$REQUEST_METHOD" = "POST" ] || return
  local length="${CONTENT_LENGTH:-0}"
  case "$length" in
    ''|*[!0-9]*) length=0 ;;
  esac
  if [ "$length" -gt 0 ] 2>/dev/null; then
    request_body=$(dd bs=1 count="$length" 2>/dev/null)
  else
    request_body=""
  fi
}

parse_form_data() {
  local data="$1" pair key value
  POST_form=""
  POST_tab=""
  [ -z "$data" ] && return
  local oldifs="$IFS"
  IFS='&'
  for pair in $data; do
    IFS="$oldifs"
    case "$pair" in
      *=*)
        key="${pair%%=*}"
        value="${pair#*=}"
        ;;
      *)
        key="$pair"
        value=""
        ;;
    esac
    key=$(urldecode "$key")
    value=$(urldecode "$value")
    case "$key" in
      form) POST_form="$value" ;;
      tab) POST_tab="$value" ;;
      vr_autostart) POST_vr_autostart="$value" ;;
      vr_channel) POST_vr_channel="$value" ;;
      vr_device_path) POST_vr_device_path="$value" ;;
      vr_duration) POST_vr_duration="$value" ;;
      vr_filename) POST_vr_filename="$value" ;;
      vr_limit) POST_vr_limit="$value" ;;
      vr_mount) POST_vr_mount="$value" ;;
      tl_enabled) POST_tl_enabled="$value" ;;
      tl_mount) POST_tl_mount="$value" ;;
      tl_filepath) POST_tl_filepath="$value" ;;
      tl_filename) POST_tl_filename="$value" ;;
      tl_interval) POST_tl_interval="$value" ;;
      tl_keep_days) POST_tl_keep_days="$value" ;;
      tl_preset_enabled) POST_tl_preset_enabled="$value" ;;
      tl_ircut) POST_tl_ircut="$value" ;;
      tl_ir850) POST_tl_ir850="$value" ;;
      tl_ir940) POST_tl_ir940="$value" ;;
      tl_white) POST_tl_white="$value" ;;
      tl_color) POST_tl_color="$value" ;;
      *) : ;;
    esac
    IFS='&'
  done
  IFS="$oldifs"
}

refresh_settings() {
  vr_read_config
  tl_read_config
  vr_defaults
  tl_defaults
}

mounts_json() {
  local saved_ifs="$IFS"
  IFS='
'
  set -- $MOUNTS_LIST
  IFS="$saved_ifs"
  local first=1
  printf '['
  for mount in "$@"; do
    [ -z "$mount" ] && continue
    if [ $first -eq 0 ]; then printf ','; fi
    printf '"%s"' "$(json_escape "$mount")"
    first=0
  done
  printf ']'
}

collect_command_output() {
  local label="$1"
  shift
  {
    printf '$ %s\n' "$label"
    "$@"
  } 2>&1 || true
}

build_state_payload() {
  MOUNTS_LIST="$(list_mounts)"
  local mounts_json_str debug_video debug_timelapse debug_crontab
  mounts_json_str=$(mounts_json)
  #debug_video="$(jct $vr_config_file get $vr_domain)"
  #debug_timelapse="$(collect_command_output "jct $tl_config_file get $tl_domain" jct "$tl_config_file" get "$tl_domain")"
  #debug_crontab="$(collect_command_output "crontab -l" crontab -l)"

  local video_channel video_duration video_limit tl_interval_num tl_keep_days_num
  video_channel="$vr_channel"
  case "$video_channel" in ''|*[!0-9]*) video_channel=0 ;; esac
  video_duration="$vr_duration"
  case "$video_duration" in ''|*[!0-9]*) video_duration=0 ;; esac
  video_limit="$vr_limit"
  case "$video_limit" in ''|*[!0-9]*) video_limit=0 ;; esac
  tl_interval_num="$tl_interval"
  case "$tl_interval_num" in ''|*[!0-9]*) tl_interval_num=0 ;; esac
  tl_keep_days_num="$tl_keep_days"
  case "$tl_keep_days_num" in ''|*[!0-9]*) tl_keep_days_num=0 ;; esac

  cat <<EOF
{
  "video": {
    "autostart": $(bool_to_json "$vr_autostart"),
    "channel": $video_channel,
    "device_path": "$(json_escape "$vr_device_path")",
    "duration": $video_duration,
    "filename": "$(json_escape "$vr_filename")",
    "limit": $video_limit,
    "mount": "$(json_escape "$vr_mount")"
  },
  "timelapse": {
    "enabled": $(bool_to_json "$tl_enabled"),
    "mount": "$(json_escape "$tl_mount")",
    "filepath": "$(json_escape "$tl_filepath")",
    "filename": "$(json_escape "$tl_filename")",
    "interval": $tl_interval_num,
    "keep_days": $tl_keep_days_num,
    "preset_enabled": $(bool_to_json "$tl_preset_enabled"),
    "presets": {
      "ircut": $(bool_to_json "$tl_ircut"),
      "ir850": $(bool_to_json "$tl_ir850"),
      "ir940": $(bool_to_json "$tl_ir940"),
      "white": $(bool_to_json "$tl_white"),
      "color": $(bool_to_json "$tl_color")
    }
  },
  "mounts": $mounts_json_str,
  "messages": {
    "strftime_hint": "$(json_escape "$STR_SUPPORTS_STRFTIME")"
  },
  "debug": {
    "video": "$debug_video",
    "timelapse": "$debug_timelapse",
    "crontab": "$debug_crontab"
  }
}
EOF
}

send_state_response() {
  local message="$1"
  refresh_settings
  local data
  data=$(build_state_payload)
  if [ -n "$message" ]; then
    send_json "{\"ok\":true,\"message\":\"$(json_escape "$message")\",\"data\":$data}"
  else
    send_json "{\"ok\":true,\"data\":$data}"
  fi
}

update_timelapse_cron() {
  local tmpfile
  tmpfile=$(mktemp) || json_error 500 "Unable to update timelapse schedule"
  if [ -f "$CRONTABS" ]; then
    cat "$CRONTABS" > "$tmpfile"
  else
    : > "$tmpfile"
  fi
  sed -i '/timelapse/d' "$tmpfile"
  printf '# run timelapse every %s minutes\n' "$tl_interval" >> "$tmpfile"
  if [ "$tl_enabled" = "true" ]; then
    printf '*/%s * * * * timelapse\n' "$tl_interval" >> "$tmpfile"
  else
    printf '#*/%s * * * * timelapse\n' "$tl_interval" >> "$tmpfile"
  fi
  if ! mv "$tmpfile" "$CRONTABS"; then
    rm -f "$tmpfile"
    json_error 500 "Unable to write timelapse schedule"
  fi
}

process_video_form() {
  refresh_settings
  vr_autostart="$POST_vr_autostart"
  vr_channel="$POST_vr_channel"
  vr_device_path="$POST_vr_device_path"
  vr_duration="$POST_vr_duration"
  vr_filename="$POST_vr_filename"
  vr_limit="$POST_vr_limit"
  vr_mount="$POST_vr_mount"
  vr_defaults

  vr_autostart=$(normalize_bool "$vr_autostart")
  case "$vr_channel" in 0|1) : ;; *) vr_channel=0 ;; esac
  if ! is_positive_int "$vr_duration"; then
    json_error 422 "Clip duration must be a positive integer"
  fi
  if ! is_positive_int "$vr_limit"; then
    json_error 422 "Storage limit must be a positive integer"
  fi
  [ -z "$vr_mount" ] && json_error 422 "Record mount cannot be empty."
  case "$vr_filename" in
    /*) vr_filename="${vr_filename#/}" ;;
  esac
  [ -z "$vr_filename" ] && json_error 422 "Record filename cannot be empty."

  vr_set_value autostart "$vr_autostart"
  vr_set_value channel "$vr_channel"
  vr_set_value device_path "$vr_device_path"
  vr_set_value duration "$vr_duration"
  vr_set_value filename "$vr_filename"
  vr_set_value limit "$vr_limit"
  vr_set_value mount "$vr_mount"

  if ! jct "$vr_config_file" import "$vr_temp_config_file"; then
    rm -f "$vr_temp_config_file"
    json_error 500 "Failed to update video recorder configuration"
  fi
  rm -f "$vr_temp_config_file"
  update_caminfo
  send_state_response "Video recorder settings updated."
}

process_timelapse_form() {
  refresh_settings
  tl_enabled="$POST_tl_enabled"
  tl_mount="$POST_tl_mount"
  tl_filepath="$POST_tl_filepath"
  tl_filename="$POST_tl_filename"
  tl_interval="$POST_tl_interval"
  tl_keep_days="$POST_tl_keep_days"
  tl_preset_enabled="$POST_tl_preset_enabled"
  tl_ircut="$POST_tl_ircut"
  tl_ir850="$POST_tl_ir850"
  tl_ir940="$POST_tl_ir940"
  tl_white="$POST_tl_white"
  tl_color="$POST_tl_color"
  tl_defaults

  tl_enabled=$(normalize_bool "$tl_enabled")
  tl_preset_enabled=$(normalize_bool "$tl_preset_enabled")
  tl_ircut=$(normalize_bool "$tl_ircut")
  tl_ir850=$(normalize_bool "$tl_ir850")
  tl_ir940=$(normalize_bool "$tl_ir940")
  tl_white=$(normalize_bool "$tl_white")
  tl_color=$(normalize_bool "$tl_color")
  case "$tl_filename" in
    /*) tl_filename="${tl_filename#/}" ;;
  esac

  if ! is_positive_int "$tl_interval"; then
    json_error 422 "Snapshot interval must be a positive integer"
  fi
  if ! is_non_negative_int "$tl_keep_days"; then
    json_error 422 "Retention days must be zero or greater"
  fi
  if [ "$tl_enabled" = "true" ]; then
    [ -z "$tl_mount" ] && json_error 422 "Timelapse mount cannot be empty."
    [ -z "$tl_filename" ] && json_error 422 "Timelapse filename cannot be empty."
  fi

  tl_set_value enabled "$tl_enabled"
  tl_set_value mount "$tl_mount"
  tl_set_value filepath "$tl_filepath"
  tl_set_value filename "$tl_filename"
  tl_set_value interval "$tl_interval"
  tl_set_value keep_days "$tl_keep_days"
  tl_set_value preset_enabled "$tl_preset_enabled"
  tl_set_value ircut "$tl_ircut"
  tl_set_value ir850 "$tl_ir850"
  tl_set_value ir940 "$tl_ir940"
  tl_set_value white "$tl_white"
  tl_set_value color "$tl_color"

  if ! jct "$tl_config_file" import "$tl_temp_config_file"; then
    rm -f "$tl_temp_config_file"
    json_error 500 "Failed to update timelapse configuration"
  fi
  rm -f "$tl_temp_config_file"
  update_timelapse_cron
  send_state_response "Timelapse recorder settings updated."
}

REQUEST_METHOD=${REQUEST_METHOD:-GET}

case "$REQUEST_METHOD" in
  GET|HEAD)
    send_state_response ""
    ;;
  POST)
    read_request_body
    parse_form_data "$request_body"
    case "$POST_form" in
      video) process_video_form ;;
      timelapse) process_timelapse_form ;;
      *) json_error 400 "Unsupported form submission" ;;
    esac
    ;;
  *)
    json_error 405 "Method not allowed" "405 Method Not Allowed"
    ;;
 esac
