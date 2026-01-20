#!/bin/sh
# shellcheck disable=SC2039
http_200() {
  printf 'Status: 200 OK\r\n'
}

http_400() {
  printf 'Status: 400 Bad Request\r\n'
}

http_412() {
  printf 'Status: 412 Precondition Failed\r\n'
}

json_header() {
  printf 'Content-Type: application/json\r\n'
  printf 'Pragma: no-cache\r\n'
  printf 'Expires: %s\r\n' "$(TZ=GMT0 date +'%a, %d %b %Y %T %Z')"
  printf 'Etag: "%s"\r\n' "$(cat /proc/sys/kernel/random/uuid)"
  printf '\r\n'
}

json_error() {
  http_412
  json_header
  printf '{"error":{"code":412,"message":"%s"}}
' "$1"
  exit 0
}

json_ok() {
  http_200
  json_header
  if [ "{" = "${1:0:1}" ]; then
    printf '{"code":200,"result":"success","message":%s}
' "$1"
  else
    printf '{"code":200,"result":"success","message":"%s"}
' "$1"
  fi
  exit 0
}


STATE_FILE="/run/prudynt/imaging.json"
IMAGING_FIFO="/run/prudynt/imagingctl"
FIELDS="brightness contrast saturation sharpness backlight wide_dynamic_range tone defog noise_reduction"

urldecode() {
  local i="${*//+/ }"
  echo -e "${i//%/\\x}"
}

is_number() {
  printf "%s" "$1" | grep -Eq '^[-+]?[0-9]+(\.[0-9]+)?$'
}

field_attr() {
  local field="$1" attr="$2"
  jct "$STATE_FILE" get "fields.${field}.${attr}" 2>/dev/null | tr -d '"' | tr -d '\n' | tr -d '\r'
}

field_supported() {
  local field="$1" supported
  supported=$(field_attr "$field" supported)
  [ "$supported" = "true" ]
}

collect_fields() {
  [ -r "$STATE_FILE" ] || return 1
  local first=1 field entry
  printf '{'
  for field in $FIELDS; do
    entry=$(jct "$STATE_FILE" get "fields.${field}" 2>/dev/null | tr -d '\n' | tr -d '\r')
    [ -z "$entry" ] && continue
    if [ $first -eq 0 ]; then
      printf ','
    fi
    printf '"%s":%s' "$field" "$entry"
    first=0
  done
  printf '}'
  return 0
}

read_fields_with_retry() {
  local attempt=0 result
  while [ $attempt -lt 5 ]; do
    result=$(collect_fields) && { echo "$result"; return 0; }
    sleep 0.1
    attempt=$((attempt + 1))
  done
  return 1
}

normalize_value() {
  local field="$1" raw="$2" min max supported
  min=$(field_attr "$field" min)
  max=$(field_attr "$field" max)
  supported=$(field_attr "$field" supported)
  [ "$supported" = "true" ] || return 1
  [ -z "$min" ] && return 1
  [ -z "$max" ] && return 1
  awk -v v="$raw" -v mn="$min" -v mx="$max" 'BEGIN {
    if (mx <= mn) {
      print "0.0000";
      exit
    }
    if (v < mn) {
      v = mn;
    } else if (v > mx) {
      v = mx;
    }
    printf "%.4f", (v - mn) / (mx - mn);
  }'
}

apply_updates() {
  local payload="SET" changed=0 field raw norm
  for field in $FIELDS; do
    eval "raw=\${$field}"
    [ -z "$raw" ] && continue
    if ! is_number "$raw"; then
      json_error "invalid value for $field"
    fi
    if ! field_supported "$field"; then
      json_error "$field is not supported"
    fi
    norm=$(normalize_value "$field" "$raw") || json_error "missing range for $field"
    payload="$payload $field=$norm"
    changed=1
  done
  [ $changed -eq 1 ] || json_error "no imaging parameters provided"
  if ! printf '%s\n' "$payload" > "$IMAGING_FIFO"; then
    json_error "failed to send imaging command"
  fi
  sleep 0.1
  local fields_json
  fields_json=$(read_fields_with_retry) || json_error "imaging state unavailable"
  json_ok "{\"fields\":$fields_json}"
}

handle_read() {
  local fields_json
  fields_json=$(read_fields_with_retry) || json_error "imaging state unavailable"
  json_ok "{\"fields\":$fields_json}"
}

parse_body() {
  local data="$1"
  [ -z "$data" ] && return
  eval "$(echo "$data" | sed 's/&/;/g')"
}

handle_post() {
  local body param value
  if [ -n "$CONTENT_LENGTH" ]; then
    body=$(dd bs=1 count="$CONTENT_LENGTH" 2>/dev/null)
  else
    body=$(cat)
  fi
  [ -n "$body" ] && parse_body "$body"

  for param in $FIELDS; do
    eval "value=\${$param}"
    [ -n "$value" ] && eval "$param=\"$(urldecode "$value")\""
  done

  apply_updates
}

case "$REQUEST_METHOD" in
  POST)
    handle_post
    ;;
  GET|"")
    handle_read
    ;;
  *)
    json_error "method not allowed"
    ;;
esac
