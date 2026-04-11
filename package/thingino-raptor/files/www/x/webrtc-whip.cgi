#!/bin/sh

set -eu

RAPTOR_CONF="/etc/raptor.conf"
BACKEND_BASE="https://127.0.0.1:8554"

send_json() {
  code="$1"
  body="$2"
  printf 'Status: %s\r\n' "$code"
  printf 'Content-Type: application/json\r\n\r\n'
  printf '%s' "$body"
}

status_line() {
  code="$1"
  case "$code" in
    200) echo "200 OK" ;;
    201) echo "201 Created" ;;
    204) echo "204 No Content" ;;
    400) echo "400 Bad Request" ;;
    401) echo "401 Unauthorized" ;;
    403) echo "403 Forbidden" ;;
    404) echo "404 Not Found" ;;
    405) echo "405 Method Not Allowed" ;;
    409) echo "409 Conflict" ;;
    500) echo "500 Internal Server Error" ;;
    502) echo "502 Bad Gateway" ;;
    503) echo "503 Service Unavailable" ;;
    *) echo "502 Bad Gateway" ;;
  esac
}

json_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e ':a;N;$!ba;s/\n/\\n/g'
}

get_webrtc_value() {
  key="$1"
  sed -n '/^\[webrtc\]/,/^\[/p' "$RAPTOR_CONF" 2>/dev/null | \
    grep "^${key}[[:space:]]*=" | head -1 | cut -d= -f2- | tr -d ' \t\r\n'
}

qs_get() {
  key="$1"
  printf '%s' "${QUERY_STRING:-}" | tr '&' '\n' | grep "^${key}=" | head -1 | cut -d= -f2-
}

url_decode() {
  printf '%b' "${1//%/\\x}"
}

webrtc_user="$(get_webrtc_value username || true)"
webrtc_pass="$(get_webrtc_value password || true)"

if [ "${REQUEST_METHOD:-}" = "POST" ]; then
  stream_raw="$(qs_get stream)"
  stream="$(url_decode "${stream_raw:-0}")"
  [ -n "$stream" ] || stream="0"

  body_file="$(mktemp /tmp/webrtc-whip-body.XXXXXX)"
  hdr_file="$(mktemp /tmp/webrtc-whip-hdr.XXXXXX)"
  req_file="$(mktemp /tmp/webrtc-whip-req.XXXXXX)"
  trap 'rm -f "$body_file" "$hdr_file" "$req_file"' EXIT INT TERM

  cat >"$req_file"

  if [ -n "$webrtc_user" ] || [ -n "$webrtc_pass" ]; then
    curl_rc=0
    curl -skS -D "$hdr_file" -o "$body_file" \
      -u "$webrtc_user:$webrtc_pass" \
      -H 'Content-Type: application/sdp' \
      --data-binary @"$req_file" \
      "$BACKEND_BASE/whip?stream=$stream" || curl_rc=$?
  else
    curl_rc=0
    curl -skS -D "$hdr_file" -o "$body_file" \
      -H 'Content-Type: application/sdp' \
      --data-binary @"$req_file" \
      "$BACKEND_BASE/whip?stream=$stream" || curl_rc=$?
  fi

  if [ "$curl_rc" -ne 0 ]; then
    send_json "502 Bad Gateway" '{"error":"backend_unreachable"}'
    exit 0
  fi

  status="$(awk 'toupper($1) ~ /^HTTP\// {code=$2} END {print code}' "$hdr_file")"
  [ -n "$status" ] || status=500
  location="$(grep -i '^Location:' "$hdr_file" | tail -1 | cut -d' ' -f2- | tr -d '\r\n')"
  sdp="$(cat "$body_file")"

  if [ "$status" -ge 200 ] && [ "$status" -lt 300 ]; then
    printf 'Status: %s\r\n' "$(status_line "$status")"
    [ -n "$location" ] && printf 'Location: %s\r\n' "$location"
    printf 'Content-Type: application/sdp\r\n\r\n'
    printf '%s' "$sdp"
  else
    printf 'Status: %s\r\n' "$(status_line "$status")"
    printf 'Content-Type: text/plain\r\n\r\n'
    printf '%s' "$sdp"
  fi

  exit 0
fi

if [ "${REQUEST_METHOD:-}" = "DELETE" ]; then
  session_raw="$(qs_get session)"
  session="$(url_decode "${session_raw:-}")"

  case "$session" in
    '')
      send_json "400 Bad Request" '{"error":"missing_session"}'
      exit 0
      ;;
    http://*|https://*)
      target="$session"
      ;;
    *)
      target="$BACKEND_BASE$session"
      ;;
  esac

  if [ -n "$webrtc_user" ] || [ -n "$webrtc_pass" ]; then
    code="$(curl -skS -o /dev/null -w '%{http_code}' -u "$webrtc_user:$webrtc_pass" -X DELETE "$target" || true)"
  else
    code="$(curl -skS -o /dev/null -w '%{http_code}' -X DELETE "$target" || true)"
  fi

  [ -n "$code" ] || code=502
  printf 'Status: %s\r\n\r\n' "$(status_line "$code")"
  exit 0
fi

if [ "${REQUEST_METHOD:-}" = "OPTIONS" ]; then
  printf 'Status: 204 No Content\r\n\r\n'
  exit 0
fi

send_json "405 Method Not Allowed" '{"error":"method_not_allowed"}'