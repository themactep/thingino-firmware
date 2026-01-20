#!/bin/sh

. /usr/share/common

request_body=""
POST_action=""
POST_fstype=""

sd_present="false"
sd_device=""
sd_device_node=""
sd_device_vendor=""
sd_device_model=""
sd_device_serial=""
sd_device_size_bytes=0
LAST_FORMAT_OUTPUT=""

json_escape() {
  printf '%s' "$1" | sed \
    -e 's/\\/\\\\/g' \
    -e 's/"/\\"/g' \
    -e "s/\r/\\r/g" \
    -e "s/\n/\\n/g"
}

base64_encode_string() {
  # Collapse command output into a compact, JSON-safe base64 blob
  printf '%s' "$1" | base64 | tr -d '\n'
}

send_json() {
  local payload="$1"
  local status="${2:-200 OK}"
  printf 'Status: %s\n' "$status"
  cat <<EOF
Content-Type: application/json
Cache-Control: no-store
Pragma: no-cache

$payload
EOF
  exit 0
}

json_error() {
  local code="${1:-400}"
  local message="$2"
  local status="${3:-400 Bad Request}"
  send_json "{\"error\":{\"code\":$code,\"message\":\"$(json_escape "$message")\"}}" "$status"
}

bool_to_json() {
  [ "$1" = "true" ] && printf 'true' || printf 'false'
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
  fi
}

urldecode() {
  local data="${1//+/ }"
  printf '%b' "${data//%/\\x}"
}

parse_form_data() {
  POST_action=""
  POST_fstype=""
  local data="$1"
  [ -n "$data" ] || return
  local oldifs="$IFS" pair key value
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
      action) POST_action="$value" ;;
      fstype) POST_fstype="$value" ;;
      *) : ;;
    esac
    IFS='&'
  done
  IFS="$oldifs"
}

read_sys_value() {
  local file="$1"
  [ -r "$file" ] || return
  tr -d '\000' < "$file" | tr -d '\r' | sed -e 's/[[:space:]]*$//' -e 's/^[[:space:]]*//'
}

detect_sdcard() {
  sd_present="false"
  sd_device=""
  sd_device_node=""
  sd_device_vendor=""
  sd_device_model=""
  sd_device_serial=""
  sd_device_size_bytes=0

  local dev block base sys_block blocks sector
  for dev in /sys/bus/mmc/devices/*; do
    [ -d "$dev" ] || continue
    if grep -q 'SD$' "$dev/type" 2>/dev/null; then
      for block in "$dev"/block/*; do
        [ -d "$block" ] || continue
        base="$(basename "$block")"
        case "$base" in
          *boot*) continue ;;
        esac
        sd_device="$base"
        break
      done
      [ -n "$sd_device" ] || continue
      sd_present="true"
      sd_device_node="/dev/$sd_device"
      sys_block="/sys/class/block/$sd_device"
      sd_device_vendor=$(read_sys_value "$sys_block/device/vendor")
      sd_device_model=$(read_sys_value "$sys_block/device/name")
      [ -n "$sd_device_model" ] || sd_device_model=$(read_sys_value "$sys_block/device/model")
      sd_device_serial=$(read_sys_value "$sys_block/device/serial")
      blocks=$(read_sys_value "$sys_block/size")
      sector=$(read_sys_value "$sys_block/queue/hw_sector_size")
      case "$blocks" in ''|*[!0-9]*) blocks=0 ;; esac
      case "$sector" in ''|*[!0-9]*) sector=512 ;; esac
      if [ "$blocks" -gt 0 ] 2>/dev/null && [ "$sector" -gt 0 ] 2>/dev/null; then
        sd_device_size_bytes=$((blocks * sector))
      else
        sd_device_size_bytes=0
      fi
      break
    fi
  done
}

sdcard_partitions() {
  df -h 2>/dev/null | awk 'NR==1 || /dev\/mmc/' 2>/dev/null
}

sdcard_mounts() {
  awk '$1 ~ /^\/dev\/mmc/' /proc/mounts 2>/dev/null
}

sdcard_fdisk() {
  [ "$sd_present" = "true" ] || return
  [ -n "$sd_device_node" ] || return
  fdisk -l "$sd_device_node" 2>/dev/null
}

device_json() {
  if [ "$sd_present" = "true" ] && [ -n "$sd_device_node" ]; then
    cat <<EOF
{
  "name": "$(json_escape "$sd_device")",
  "node": "$(json_escape "$sd_device_node")",
  "vendor": "$(json_escape "$sd_device_vendor")",
  "model": "$(json_escape "$sd_device_model")",
  "serial": "$(json_escape "$sd_device_serial")",
  "size_bytes": $sd_device_size_bytes
}
EOF
  else
    printf 'null'
  fi
}

build_state_payload() {
  detect_sdcard
  local partitions mounts fdisk partitions_b64 mounts_b64 fdisk_b64 format_last_output_b64
  partitions="$(sdcard_partitions)"
  mounts="$(sdcard_mounts)"
  fdisk="$(sdcard_fdisk)"
  partitions_b64="$(base64_encode_string "$partitions")"
  mounts_b64="$(base64_encode_string "$mounts")"
  fdisk_b64="$(base64_encode_string "$fdisk")"
  format_last_output_b64="$(base64_encode_string "$LAST_FORMAT_OUTPUT")"
  cat <<EOF
{
  "has_sdcard": $(bool_to_json "$sd_present"),
  "device": $(device_json),
  "reports": {
    "partitions_b64": "$(json_escape "$partitions_b64")",
    "mounts_b64": "$(json_escape "$mounts_b64")"
  },
  "format": {
    "last_output_b64": "$(json_escape "$format_last_output_b64")"
  },
  "filesystems": [
    {"id":"exfat","label":"ExFAT","description":"Best for large files and modern OS support.","recommended":true},
    {"id":"fat32","label":"FAT32","description":"Maximum compatibility with legacy devices."}
  ],
  "messages": {
    "format_warning": "Formatting erases every file on the SD card.",
    "not_present": "Insert or reseat the SD card to manage it here."
  },
  "debug": {
    "fdisk_b64": "$(json_escape "$fdisk_b64")",
    "partitions_b64": "$(json_escape "$partitions_b64")",
    "mounts_b64": "$(json_escape "$mounts_b64")"
  }
}
EOF
}

send_state_response() {
  local message="$1"
  local payload
  payload=$(build_state_payload)
  if [ -n "$message" ]; then
    send_json "{\"ok\":true,\"message\":\"$(json_escape "$message")\",\"data\":$payload}"
  else
    send_json "{\"ok\":true,\"data\":$payload}"
  fi
}

format_sdcard() {
  detect_sdcard
  [ "$sd_present" = "true" ] || json_error 404 "No SD card detected." "404 Not Found"
  local fs="${POST_fstype:-exfat}"
  fs=$(printf '%s' "$fs" | tr 'A-Z' 'a-z')
  case "$fs" in
    exfat|fat32) : ;;
    "") fs="exfat" ;;
    *) json_error 422 "Filesystem '$fs' is not supported." ;;
  esac
  if ! LAST_FORMAT_OUTPUT=$(formatsd "$fs" 2>&1); then
    json_error 500 "Formatting failed: $LAST_FORMAT_OUTPUT" "500 Internal Server Error"
  fi
  send_state_response "SD card formatted successfully."
}

handle_post() {
  local action="${POST_action:-format}"
  case "$action" in
    ''|format) format_sdcard ;;
    *) json_error 400 "Unsupported action '$action'." ;;
  esac
}

read_request_body
parse_form_data "$request_body"

case "$REQUEST_METHOD" in
  ''|GET) send_state_response "" ;;
  POST) handle_post ;;
  *) json_error 405 "Method $REQUEST_METHOD is not allowed." "405 Method Not Allowed" ;;
esac
