#!/bin/sh

ONVIF_CONFIG="/etc/onvif.json"
PRUDYNT_CONFIG="/etc/prudynt.json"

emit_json() {
  status="$1"
  shift
  [ -n "$status" ] && printf 'Status: %s\n' "$status"
  cat <<EOF
Content-Type: application/json
Cache-Control: no-store
Pragma: no-cache

$1
EOF
  exit 0
}

json_error() {
  status="${1:-400 Bad Request}"
  text="$2"
  code="${3:-error}"
  emit_json "$status" "$(printf '{"error":{"code":"%s","message":"%s"}}' "$(json_escape "$code")" "$(json_escape "$text")")"
}

json_escape() {
  printf '%s' "$1" | sed \
    -e 's/\\/\\\\/g' \
    -e 's/"/\\"/g' \
    -e 's/\r/\\r/g' \
    -e 's/\n/\\n/g'
}

read_config() {
  username=$(jct "$ONVIF_CONFIG" get "server.username" 2>/dev/null)
  password=$(jct "$ONVIF_CONFIG" get "server.password" 2>/dev/null)
  onvif_port=$(jct "$ONVIF_CONFIG" get "server.port" 2>/dev/null)

  rtsp_port=$(jct "$PRUDYNT_CONFIG" get "rtsp.port" 2>/dev/null)
  rtsp_ch0=$(jct "$PRUDYNT_CONFIG" get "stream0.rtsp_endpoint" 2>/dev/null)
  rtsp_ch1=$(jct "$PRUDYNT_CONFIG" get "stream1.rtsp_endpoint" 2>/dev/null)
  rtsp_mic=$(jct "$PRUDYNT_CONFIG" get "rtsp.audio_only_endpoint" 2>/dev/null)

  [ -z "$username" ] && username=$(jct "$PRUDYNT_CONFIG" get "rtsp.username" 2>/dev/null)
  [ -z "$password" ] && password=$(jct "$PRUDYNT_CONFIG" get "rtsp.password" 2>/dev/null)
}

send_config() {
  printf '{"username":"%s","password":"%s","onvif_port":"%s","rtsp_port":"%s","rtsp_ch0":"%s","rtsp_ch1":"%s","rtsp_mic":"%s"}\n' \
    "$(json_escape "$username")" \
    "$(json_escape "$password")" \
    "$(json_escape "$onvif_port")" \
    "$(json_escape "$rtsp_port")" \
    "$(json_escape "$rtsp_ch0")" \
    "$(json_escape "$rtsp_ch1")" \
    "$(json_escape "$rtsp_mic")"
}

read_body() {
  req_file=$(mktemp /tmp/config-rtsp-body.XXXXXX)
  if [ -n "$CONTENT_LENGTH" ]; then
    dd bs=1 count="$CONTENT_LENGTH" 2>/dev/null >"$req_file"
  else
    cat >"$req_file"
  fi
}

cleanup() {
  [ -n "$req_file" ] && rm -f "$req_file"
}

ensure_file() {
  [ -f "$1" ] || printf '{}\n' >"$1"
}

update_password() {
  new_password=$(jct "$req_file" get password 2>/dev/null)
  [ -n "$new_password" ] || json_error "400 Bad Request" "Password is required" "missing_password"

  read_config

  ensure_file "$ONVIF_CONFIG"
  ensure_file "$PRUDYNT_CONFIG"

  jct "$ONVIF_CONFIG" set "server.password" "$new_password" >/dev/null 2>&1
  jct "$PRUDYNT_CONFIG" set "rtsp.password" "$new_password" >/dev/null 2>&1

  username=${username:-$(jct "$PRUDYNT_CONFIG" get "rtsp.username" 2>/dev/null)}
  [ -n "$username" ] || username="thingino"

  if command -v chpasswd >/dev/null 2>&1; then
    echo "$username:$new_password" | chpasswd -c sha512 >/dev/null 2>&1 || true
  fi

  if command -v service >/dev/null 2>&1; then
    for svc in onvif_discovery onvif_notify prudynt; do
      service restart "$svc" >/dev/null 2>&1 || true
    done
  fi

  emit_json "" '{"status":"ok"}'
}

trap cleanup EXIT

case "$REQUEST_METHOD" in
  POST)
    read_body
    update_password
    ;;
  GET|"")
    read_config
    emit_json "" "$(send_config)"
    ;;
  *)
    json_error "405 Method Not Allowed" "Unsupported method" "unsupported_method"
    ;;
esac
