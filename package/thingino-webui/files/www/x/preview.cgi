#!/bin/sh

. /var/www/x/auth.sh
require_auth

OSD_FONT_PATH="/usr/share/fonts"
DEFAULT_OSD_FONT_FILE="${OSD_FONT_PATH}/default.ttf"
LEGACY_UPLOADED_FONT_FILE="${OSD_FONT_PATH}/uploaded.ttf"
OVERLAY_DEFAULT_OSD_FONT_FILE="/overlay/usr/share/fonts/default.ttf"
SENSOR_IQ_PATH="/etc/sensor"
SENSOR_IQ_UPLOAD_PATH="/opt/sensor"
SENSOR_MODEL=$(cat /proc/jz/sensor/name 2>/dev/null)
SOC_MODEL=$(soc -f 2>/dev/null)
SENSOR_IQ_FILE="${SENSOR_MODEL}-${SOC_MODEL}.bin"
UPLOADED_SENSOR_IQ_FILE="${SENSOR_IQ_UPLOAD_PATH}/uploaded.bin"

send_redirect() {
  local target="$1"
  printf 'Status: 303 See Other\r\n'
  printf 'Location: %s\r\n' "$target"
  printf 'Cache-Control: no-store\r\n'
  printf 'Connection: close\r\n\r\n'
  exit 0
}

send_error() {
  local status="$1"
  local message="$2"
  printf 'Status: %s\r\n' "$status"
  printf 'Content-Type: text/plain\r\n'
  printf 'Cache-Control: no-store\r\n'
  printf 'Connection: close\r\n\r\n'
  printf '%s\n' "$message"
  exit 1
}

extract_part_value() {
  local request_file="$1"
  local part_index="$2"

  awk -v RS='\r\n\r\n' -v target="$part_index" '
    NR == target {
      sub(/\r\n--.*/, "", $0)
      gsub(/[\r\n]/, "", $0)
      print
      exit
    }
  ' "$request_file"
}

default_redirect_for_form() {
  case "$1" in
    sensor)
      printf '/streamer-sensor.html'
      ;;
    *)
      printf '/preview.html'
      ;;
  esac
}

redirect_target() {
  case "$HTTP_REFERER" in
    '' )
      default_redirect_for_form "$1"
      ;;
    http://*|https://*|/*)
      printf '%s' "$HTTP_REFERER"
      ;;
    *)
      default_redirect_for_form "$1"
      ;;
  esac
}

extract_upload_payload() {
  local request_file="$1"
  local output_file="$2"
  local part_index="$3"
  local trailer start_offset total_size payload_size

  trailer=$(printf '\r\n--%s--\r\n' "$BOUNDARY" | wc -c | tr -d '[:space:]') || return 1
  start_offset=$(awk -v RS='\r\n\r\n' -v target="$part_index" '
    { offset += length($0) + 4 }
    NR == target - 1 { print offset; exit }
  ' "$request_file") || return 1
  total_size=$(wc -c < "$request_file" | tr -d '[:space:]') || return 1

  case "$start_offset" in
    ''|*[!0-9]*) return 1 ;;
  esac
  case "$total_size" in
    ''|*[!0-9]*) return 1 ;;
  esac
  case "$trailer" in
    ''|*[!0-9]*) return 1 ;;
  esac

  payload_size=$((total_size - start_offset - trailer))
  [ "$payload_size" -gt 0 ] 2>/dev/null || return 1

  dd if="$request_file" of="$output_file" bs=1 skip="$start_offset" count="$payload_size" 2>/dev/null || return 1
  [ -s "$output_file" ] || return 1
}

handle_font_upload() {
  local upload_file="$1"

  mv "$upload_file" "$DEFAULT_OSD_FONT_FILE" || return 1
  chmod 644 "$DEFAULT_OSD_FONT_FILE" >/dev/null 2>&1 || return 1
  rm -f "$LEGACY_UPLOADED_FONT_FILE"
  service restart prudynt >/dev/null 2>&1 &
}

handle_font_reset() {
  rm -f "$OVERLAY_DEFAULT_OSD_FONT_FILE" || return 1
  rm -f "$LEGACY_UPLOADED_FONT_FILE"
  mount -o remount / >/dev/null 2>&1 || return 1
  service restart prudynt >/dev/null 2>&1 &
}

normalize_legacy_uploaded_font_references() {
  local live_update current_path payload_written=0 stream_id

  live_update=$(mktemp /tmp/preview-font-live.XXXXXX) || return 1
  printf '{' > "$live_update"

  for stream_id in 0 1; do
    current_path=$(jct /etc/prudynt.json get "stream${stream_id}.osd.font_path" 2>/dev/null | tr -d '\"\r\n')
    [ "$current_path" = "$LEGACY_UPLOADED_FONT_FILE" ] || continue

    jct /etc/prudynt.json set "stream${stream_id}.osd.font_path" "$DEFAULT_OSD_FONT_FILE" >/dev/null 2>&1 || {
      rm -f "$live_update"
      return 1
    }

    if [ "$payload_written" -eq 1 ]; then
      printf ',' >> "$live_update"
    fi
    printf '"stream%s":{"osd":{"font_path":"%s"}}' "$stream_id" "$DEFAULT_OSD_FONT_FILE" >> "$live_update"
    payload_written=1
  done

  if [ "$payload_written" -eq 1 ]; then
    printf ',"action":{"restart_thread":10}}' >> "$live_update"
    prudyntctl json - < "$live_update" >/dev/null 2>&1 || {
      rm -f "$live_update"
      return 1
    }
  fi

  rm -f "$live_update"
}

handle_sensor_upload() {
  local upload_file="$1"

  mkdir -p "$SENSOR_IQ_UPLOAD_PATH" "$SENSOR_IQ_PATH" || return 1
  mv "$upload_file" "$UPLOADED_SENSOR_IQ_FILE" || return 1
  ln -sf "$UPLOADED_SENSOR_IQ_FILE" "$SENSOR_IQ_PATH/$SENSOR_IQ_FILE" || return 1
  service restart prudynt >/dev/null 2>&1 &
}

case "${REQUEST_METHOD:-GET}" in
  POST)
    ;;
  *)
    send_error '405 Method Not Allowed' 'Method not allowed.'
    ;;
esac

case "${CONTENT_TYPE:-}" in
  multipart/form-data*)
    BOUNDARY=$(printf '%s' "$CONTENT_TYPE" | sed -n 's/.*boundary=//p')
    BOUNDARY=${BOUNDARY%%;*}
    BOUNDARY=${BOUNDARY%\"}
    BOUNDARY=${BOUNDARY#\"}
    [ -n "$BOUNDARY" ] || send_error '400 Bad Request' 'Missing multipart boundary.'
    ;;
  *)
    send_error '415 Unsupported Media Type' 'Unsupported content type.'
    ;;
esac

case "${CONTENT_LENGTH:-}" in
  ''|*[!0-9]*)
    send_error '411 Length Required' 'Invalid content length.'
    ;;
esac

[ "$CONTENT_LENGTH" -gt 0 ] 2>/dev/null || send_error '411 Length Required' 'Empty upload payload.'

REQUEST_FILE=$(mktemp /tmp/preview-upload.XXXXXX) || send_error '500 Internal Server Error' 'Unable to allocate request buffer.'
UPLOAD_FILE=$(mktemp /tmp/preview-file.XXXXXX) || {
  rm -f "$REQUEST_FILE"
  send_error '500 Internal Server Error' 'Unable to allocate upload buffer.'
}

cleanup() {
  rm -f "$REQUEST_FILE" "$UPLOAD_FILE"
}

trap cleanup EXIT INT TERM

dd bs=1 count="$CONTENT_LENGTH" of="$REQUEST_FILE" 2>/dev/null || send_error '500 Internal Server Error' 'Failed to read upload payload.'

UPLOAD_FORM=$(extract_part_value "$REQUEST_FILE" 2)

[ -n "$UPLOAD_FORM" ] || send_error '400 Bad Request' 'Missing upload form type.'

case "$UPLOAD_FORM" in
  font)
    extract_upload_payload "$REQUEST_FILE" "$UPLOAD_FILE" 3 || send_error '400 Bad Request' 'Failed to extract uploaded file.'
    handle_font_upload "$UPLOAD_FILE" || send_error '500 Internal Server Error' 'Failed to install uploaded font.'
    normalize_legacy_uploaded_font_references || send_error '500 Internal Server Error' 'Failed to normalize font configuration.'
    ;;
  font-reset)
    handle_font_reset || send_error '500 Internal Server Error' 'Failed to restore firmware font.'
    normalize_legacy_uploaded_font_references || send_error '500 Internal Server Error' 'Failed to normalize font configuration.'
    ;;
  sensor)
    extract_upload_payload "$REQUEST_FILE" "$UPLOAD_FILE" 3 || send_error '400 Bad Request' 'Failed to extract uploaded file.'
    handle_sensor_upload "$UPLOAD_FILE" || send_error '500 Internal Server Error' 'Failed to install sensor IQ file.'
    ;;
  *)
    send_error '400 Bad Request' 'Unsupported upload form.'
    ;;
esac

send_redirect "$(redirect_target "$UPLOAD_FORM")"