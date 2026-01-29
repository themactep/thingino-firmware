#!/bin/sh

# Check authentication
. /var/www/x/auth.sh
require_auth

. /usr/share/common

API_PATH="/x/tool-upgrade.cgi"
UPLOAD_TARGET="/tmp/fw-web.bin"
SYSUPGRADE_BIN="/sbin/sysupgrade"
OTA_PRE_COMMAND="touch /tmp/webupgrade;"

REQUEST_ACTION=""
REQUEST_PARTITION=""
POST_action=""
POST_option=""
REQUEST_BODY=""

json_escape() {
  printf '%s' "$1" | sed \
    -e 's/\\/\\\\/g' \
    -e 's/"/\\"/g' \
    -e "s/\r/\\r/g" \
    -e "s/\n/\\n/g"
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

urldecode() {
  local data="${1//+/ }"
  printf '%b' "${data//%/\\x}"
}

parse_query_string() {
  local data="$1" pair key value
  [ -n "$data" ] || return
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
      action) REQUEST_ACTION="$value" ;;
      partition) REQUEST_PARTITION="$value" ;;
      *) : ;;
    esac
    IFS='&'
  done
  IFS="$oldifs"
}

read_request_body() {
  REQUEST_BODY=""
  local length="${CONTENT_LENGTH:-0}"
  case "$length" in
    ''|*[!0-9]*) length=0 ;;
  esac
  if [ "$length" -gt 0 ] 2>/dev/null; then
    REQUEST_BODY=$(dd bs=1 count="$length" 2>/dev/null)
  fi
}

parse_form_data() {
  local data="$1" pair key value
  POST_action=""
  POST_option=""
  [ -n "$data" ] || return
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
      action) POST_action="$value" ;;
      option) POST_option="$value" ;;
      *) : ;;
    esac
    IFS='&'
  done
  IFS="$oldifs"
}

list_mtd_partitions() {
  awk -F: '/^mtd[0-9]+/ { gsub(/ /, "", $1); print $1 }' /proc/mtd 2>/dev/null
}

partitions_json() {
  local data="$1"
  local first=1
  printf '['
  for part in $data; do
    [ -n "$part" ] || continue
    if [ $first -eq 0 ]; then printf ','; fi
    printf '{"id":"%s","label":"%s","download_url":"%s"}' \
      "$(json_escape "$part")" \
      "$(json_escape "$part")" \
      "$(json_escape "$API_PATH?partition=$part")"
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

file_size_bytes() {
  local file="$1"
  [ -f "$file" ] || return
  wc -c < "$file" 2>/dev/null | tr -d ' '
}

build_state_payload() {
  local partitions partitions_json_str proc_mtd_table proc_mtd_table_b64
  local debug_proc_mtd debug_proc_mtd_b64 debug_df debug_df_b64 debug_upload debug_upload_b64 host stamp
  local backup_filename download_url upload_present upload_size
  partitions=$(list_mtd_partitions)
  partitions_json_str=$(partitions_json "$partitions")
  proc_mtd_table=$(cat /proc/mtd 2>/dev/null)
  proc_mtd_table_b64=$(printf '%s' "$proc_mtd_table" | base64 | tr -d '\n')
  debug_proc_mtd=$(collect_command_output 'cat /proc/mtd' cat /proc/mtd)
  debug_proc_mtd_b64=$(printf '%s' "$debug_proc_mtd" | base64 | tr -d '\n')
  debug_df=$(collect_command_output 'df -h' df -h)
  debug_df_b64=$(printf '%s' "$debug_df" | base64 | tr -d '\n')
  debug_upload=$(collect_command_output "ls -lh $UPLOAD_TARGET" ls -lh "$UPLOAD_TARGET")
  debug_upload_b64=$(printf '%s' "$debug_upload" | base64 | tr -d '\n')
  host=$(hostname 2>/dev/null)
  [ -n "$host" ] || host="camera"
  stamp=$(date +%Y%m%d 2>/dev/null)
  [ -n "$stamp" ] || stamp="00000000"
  backup_filename="backup-${host}-${stamp}.tar.gz"
  download_url="$API_PATH?action=generate_backup"
  upload_present="false"
  upload_size=0
  if [ -s "$UPLOAD_TARGET" ]; then
    upload_present="true"
    upload_size=$(file_size_bytes "$UPLOAD_TARGET")
    [ -n "$upload_size" ] || upload_size=0
  fi
  cat <<EOF
{
  "backup": {
    "download_url": "$(json_escape "$download_url")",
    "filename": "$(json_escape "$backup_filename")",
    "description": "Creates a tar.gz archive of /etc for safekeeping."
  },
  "mtd": {
    "partitions": $partitions_json_str,
    "download_base": "$(json_escape "$API_PATH?partition=")",
    "table_base64": "$(json_escape "$proc_mtd_table_b64")",
    "warning": "Dumping flash partitions is intended for recovery experts."
  },
  "ota": {
    "options": [
      {"id":"full","label":"Full image","flag":"-f","description":"Will erase everything and install a pristine new image. No customization will survive. You will have to reconfigure the system from scratch."},
      {"id":"partial","label":"Partial update","flag":"-p","description":"Will keep overlay partition with configuration and changed files. Most likely will end up in conflicts, so you might need to reset and reconfigure the system."},
      {"id":"bootloader","label":"Bootloader","flag":"-b","description":"Writes new bootloader only. Relatively safe operation when you know what you are doing. Intended for developers."}
    ],
    "pre_command": "$(json_escape "$OTA_PRE_COMMAND")",
    "command": "$(json_escape "$SYSUPGRADE_BIN")",
    "notes": "Uses sysupgrade to fetch the latest Thingino release from GitHub."
  },
  "upload": {
    "target": "$(json_escape "$UPLOAD_TARGET")",
    "pre_command": "$(json_escape "$OTA_PRE_COMMAND")",
    "command": "$(json_escape "$SYSUPGRADE_BIN $UPLOAD_TARGET")",
    "has_image": $(bool_to_json "$upload_present"),
    "size_bytes": $upload_size
  },
  "messages": {
    "backup_warning": "The archive includes Wi-Fi credentials, SSH certificates, and accounts for various services. Store securely!",
    "ota_warning": "OTA upgrade will reboot the camera when it finishes.",
    "flash_warning": "Uploading an invalid image may render the device unresponsive!"
  },
  "debug": {
    "proc_mtd_base64": "$(json_escape "$debug_proc_mtd_b64")",
    "df_base64": "$(json_escape "$debug_df_b64")",
    "upload_base64": "$(json_escape "$debug_upload_b64")"
  }
}
EOF
}

send_state_response() {
  local message="$1"
  local command="$2"
  local data response
  data=$(build_state_payload)
  response="{\"ok\":true"
  if [ -n "$message" ]; then
    response="$response,\"message\":\"$(json_escape "$message")\""
  fi
  if [ -n "$command" ]; then
    response="$response,\"command\":\"$(json_escape "$command")\""
  fi
  response="$response,\"data\":$data}"
  send_json "$response"
}

handle_backup_download() {
  local host stamp
  host=$(hostname 2>/dev/null)
  [ -n "$host" ] || host="camera"
  stamp=$(date +%Y-%m-%d 2>/dev/null)
  printf 'Content-Type: application/octet-stream\r\n'
  printf 'Content-Disposition: attachment; filename=backup-%s-%s.tar.gz\r\n\r\n' "$host" "$stamp"
  tar -cf - /etc 2>/dev/null | gzip
  exit 0
}

handle_partition_download() {
  local part="$REQUEST_PARTITION"
  [ -n "$part" ] || json_error 400 "Partition parameter is required."
  if [ -e "/dev/$part" ]; then
    printf 'Content-Type: application/octet-stream\r\n'
    printf 'Content-Disposition: attachment; filename=%s.bin\r\n\r\n' "$part"
    cat "/dev/$part"
    exit 0
  fi
  printf 'Content-Type: text/plain\r\n\r\n'
  printf 'Error: Invalid or missing partition.'
  exit 1
}

ota_command_for_option() {
  local option="$1" flag=""
  case "$(printf '%s' "$option" | tr 'A-Z' 'a-z')" in
    bootloader) flag="-b" ;;
    full) flag="-f" ;;
    ''|partial) flag="-p" ;;
    *) return 1 ;;
  esac
  if [ -n "$flag" ]; then
    printf '%s%s %s' "$OTA_PRE_COMMAND" "$SYSUPGRADE_BIN" "$flag"
  else
    printf '%s%s' "$OTA_PRE_COMMAND" "$SYSUPGRADE_BIN"
  fi
}

handle_ota_command() {
  local cmd
  cmd=$(ota_command_for_option "$POST_option") || json_error 422 "Unsupported OTA option."
  send_state_response "" "$cmd"
}

save_upload_payload() {
  local boundary tmpfile
  if [ -z "$CONTENT_TYPE" ]; then
    json_error 400 "Missing Content-Type header for upload."
  fi
  case "$CONTENT_TYPE" in
    multipart/form-data*)
      boundary=$(printf '%s' "$CONTENT_TYPE" | sed -n 's/.*boundary=//p')
      boundary=${boundary%%;*}
      boundary=${boundary%\"}
      boundary=${boundary#\"}
      [ -n "$boundary" ] || json_error 400 "Unable to determine multipart boundary."
      ;;
    *)
      json_error 415 "Unsupported Content-Type for firmware upload."
      ;;
  esac
  local length="${CONTENT_LENGTH:-0}"
  case "$length" in
    ''|*[!0-9]*) json_error 411 "Invalid Content-Length." ;;
  esac
  if [ "$length" -le 0 ] 2>/dev/null; then
    json_error 411 "Empty upload payload."
  fi
  tmpfile=$(mktemp /tmp/fwupload.XXXXXX) || json_error 500 "Unable to allocate temporary file."
  if ! dd bs=1 count="$length" of="$tmpfile" 2>/dev/null; then
    rm -f "$tmpfile"
    json_error 500 "Failed to buffer upload payload."
  fi
  local trailer
  trailer=$(printf -- '--%s--' "$boundary" | wc -c)
  awk -v RS='\r\n\r\n' 'NR==2 { printf "%s", $0 }' "$tmpfile" | head -c -"$trailer" > "$UPLOAD_TARGET"
  local status=$?
  rm -f "$tmpfile"
  if [ $status -ne 0 ] || [ ! -s "$UPLOAD_TARGET" ]; then
    json_error 500 "Failed to extract firmware file."
  fi
}

handle_firmware_upload() {
  save_upload_payload
  chmod 600 "$UPLOAD_TARGET" 2>/dev/null || true
  sync
  local cmd="$SYSUPGRADE_BIN $UPLOAD_TARGET"
  send_state_response "Firmware uploaded. Ready to flash." "$cmd"
}

parse_query_string "$QUERY_STRING"

case "${REQUEST_METHOD:-GET}" in
  GET|HEAD|'')
    if [ "x$REQUEST_METHOD" = "xHEAD" ]; then
      send_json '{"ok":true}'
    fi
    if [ "${REQUEST_ACTION}" = "generate_backup" ]; then
      handle_backup_download
    fi
    if [ -n "$REQUEST_PARTITION" ]; then
      handle_partition_download
    fi
    send_state_response ""
    ;;
  POST)
    case "${CONTENT_TYPE:-}" in
      multipart/form-data*)
        handle_firmware_upload
        ;;
      *)
        read_request_body
        parse_form_data "$REQUEST_BODY"
        case "$POST_action" in
          ota|ota-command)
            handle_ota_command
            ;;
          ''|*)
            json_error 400 "Unsupported action '${POST_action}'."
            ;;
        esac
        ;;
    esac
    ;;
  *)
    json_error 405 "Method $REQUEST_METHOD is not allowed." "405 Method Not Allowed"
    ;;
esac
