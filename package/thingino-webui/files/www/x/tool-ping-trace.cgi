#!/bin/sh

. /usr/share/common

DEFAULT_PACKET_SIZE=56
DEFAULT_COUNT=5
MIN_PACKET_SIZE=56
MAX_PACKET_SIZE=65535
MIN_COUNT=1
MAX_COUNT=30

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

urldecode() {
  local data="${1//+/ }"
  printf '%b' "${data//%/\\x}"
}

read_body() {
  request_body=""
  if [ "$REQUEST_METHOD" = "POST" ]; then
    local length="${CONTENT_LENGTH:-0}"
    case "$length" in
      ''|*[!0-9]*) length=0 ;;
    esac
    if [ "$length" -gt 0 ] 2>/dev/null; then
      request_body=$(dd bs=1 count="$length" 2>/dev/null)
    fi
  else
    request_body="$QUERY_STRING"
  fi
}

parse_params() {
  local data="$1" pair key value
  form_action=""
  form_target=""
  form_interface=""
  form_packet_size=""
  form_count=""
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
    value=$(urldecode "$value")
    case "$key" in
      action|tools_action) form_action="$value" ;;
      target|tools_target) form_target="$value" ;;
      interface|tools_interface) form_interface="$value" ;;
      packet_size|tools_packet_size) form_packet_size="$value" ;;
      count|duration|tools_duration) form_count="$value" ;;
    esac
    IFS='&'
  done
  IFS="$oldifs"
}

list_interfaces() {
  if command -v ip >/dev/null 2>&1; then
    ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | sed 's/@.*//' | grep -v '^lo$'
  else
    ifconfig 2>/dev/null | awk -F'[ :]' '/^[[:alnum:]]/{print $1}' | sed 's/:.*//' | grep -v '^lo$'
  fi
}

interfaces_json() {
  local json='["auto"'
  if [ -n "$AVAILABLE_INTERFACES" ]; then
    while IFS= read -r iface; do
      [ -z "$iface" ] && continue
      json="$json,\"$(json_escape "$iface")\""
    done <<EOF
$AVAILABLE_INTERFACES
EOF
  fi
  json="$json]"
  printf '%s' "$json"
}

is_valid_interface() {
  local needle="$1"
  [ "$needle" = "auto" ] && return 0
  while IFS= read -r iface; do
    [ "$iface" = "$needle" ] && return 0
  done <<EOF
$AVAILABLE_INTERFACES
EOF
  return 1
}

encode_command() {
  printf '%s' "$1" | base64 | tr -d '\n\r'
}

build_command() {
  local action="$1" target="$2" iface="$3" psize="$4" count="$5" cmd
  if [ "$action" = "trace" ]; then
    cmd="traceroute -q $count -w 1"
    [ "$iface" != "auto" ] && cmd="$cmd -i $iface"
    cmd="$cmd $target $psize"
  else
    cmd="ping -s $psize -c $count"
    [ "$iface" != "auto" ] && cmd="$cmd -I $iface"
    cmd="$cmd $target"
  fi
  printf '%s' "$cmd"
}

build_metadata_payload() {
  cat <<EOF
{
  "interfaces": $(interfaces_json),
  "defaults": {
    "action": "ping",
    "packet_size": $DEFAULT_PACKET_SIZE,
    "count": $DEFAULT_COUNT,
    "interface": "auto"
  },
  "limits": {
    "packet_size": {"min": $MIN_PACKET_SIZE, "max": $MAX_PACKET_SIZE},
    "count": {"min": $MIN_COUNT, "max": $MAX_COUNT}
  },
  "actions": [
    {"id": "ping", "label": "Ping", "description": "Send ICMP echo requests"},
    {"id": "trace", "label": "Traceroute", "description": "Trace network route with traceroute"}
  ]
}
EOF
}

handle_get() {
  send_json "$(build_metadata_payload)"
}

handle_post() {
  read_body
  parse_params "$request_body"

  local action target iface psize count command encoded
  action="${form_action:-ping}"
  case "$action" in
    ping|trace) ;;
    *) json_error 400 "Unsupported action" ;;
  esac

  target="${form_target:-}"
  target=$(printf '%s' "$target" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
  [ -z "$target" ] && json_error 422 "Target is required"
  case "$target" in
    *[!A-Za-z0-9._:%\[\]-]*)
      json_error 422 "Target contains invalid characters"
      ;;
  esac

  psize="${form_packet_size:-$DEFAULT_PACKET_SIZE}"
  case "$psize" in
    ''|*[!0-9]*) json_error 422 "Packet size must be numeric" ;;
  esac
  if [ "$psize" -lt $MIN_PACKET_SIZE ] || [ "$psize" -gt $MAX_PACKET_SIZE ]; then
    json_error 422 "Packet size must be between $MIN_PACKET_SIZE and $MAX_PACKET_SIZE"
  fi

  count="${form_count:-$DEFAULT_COUNT}"
  case "$count" in
    ''|*[!0-9]*) json_error 422 "Packet count must be numeric" ;;
  esac
  if [ "$count" -lt $MIN_COUNT ] || [ "$count" -gt $MAX_COUNT ]; then
    json_error 422 "Packet count must be between $MIN_COUNT and $MAX_COUNT"
  fi

  iface="${form_interface:-auto}"
  [ -z "$iface" ] && iface="auto"
  if ! is_valid_interface "$iface"; then
    json_error 422 "Unknown interface"
  fi

  command=$(build_command "$action" "$target" "$iface" "$psize" "$count") || json_error 500 "Unable to build command"
  encoded=$(encode_command "$command") || json_error 500 "Unable to encode command"

  send_json "$(cat <<EOF
{
  "command":"$(json_escape "$command")",
  "stream":"/x/run.cgi?cmd=$encoded",
  "encoded":"$(json_escape "$encoded")"
}
EOF
)"
}

AVAILABLE_INTERFACES="$(list_interfaces)"

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
