#!/bin/sh

# Check authentication
. /var/www/x/auth.sh
require_auth

. /usr/share/common

DOMAIN="wireguard"
CONFIG_FILE="/etc/thingino.json"
TMP_FILE=""
REQ_FILE=""
RESP_FILE=""
ERR_FILE=""
WG_DEV="wg0"

cleanup() {
  [ -n "$TMP_FILE" ] && rm -f "$TMP_FILE"
  [ -n "$REQ_FILE" ] && rm -f "$REQ_FILE"
  [ -n "$RESP_FILE" ] && rm -f "$RESP_FILE"
  [ -n "$ERR_FILE" ] && rm -f "$ERR_FILE"
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
Connection: close

$1
EOF
  exit 0
}

json_error() {
  code="${1:-400}"
  message="$2"
  send_json "{\"error\":{\"code\":$code,\"message\":\"$(json_escape "$message")\"}}" "${3:-400 Bad Request}"
}

ensure_config() {
  if [ ! -f "$CONFIG_FILE" ]; then
    umask 077
    echo '{}' >"$CONFIG_FILE"
  fi
}

read_domain_json() {
  ensure_config
  local data
  data=$(jct "$CONFIG_FILE" get "$DOMAIN" 2>/dev/null)
  case "$data" in
    ""|null)
      data='{}'
      ;;
  esac
  printf '%s' "$data"
}

append_json_field() {
  local json="$1"
  local key="$2"
  local value="$3"
  local mode="${4:-string}"

  json=$(printf '%s' "$json" | tr -d '\n')
  [ -n "$json" ] || json='{}'

  local head tail sep formatted
  head="${json%?}"
  tail="}"
  if [ "$json" = '{}' ]; then
    head='{'
    sep=''
  else
    sep=','
  fi

  if [ "$mode" = "raw" ]; then
    formatted="$value"
  else
    formatted="\"$(json_escape "$value")\""
  fi

  printf '%s%s"%s":%s%s' "$head" "$sep" "$key" "$formatted" "$tail"
}

is_wg_up() {
  ip link show "$WG_DEV" 2>/dev/null | grep -q UP
}

wg_supported() {
  command -v wg >/dev/null 2>&1
}

derive_public_key() {
  local private_key="$1"

  [ -n "$private_key" ] || return 0
  printf '%s\n' "$private_key" | wg pubkey 2>/dev/null
}

generate_private_key() {
  wg genkey 2>/dev/null
}

generate_preshared_key() {
  wg genpsk 2>/dev/null
}

http_fetch() {
  local url="$1"

  RESP_FILE=$(mktemp /tmp/${DOMAIN}-fetch-response.XXXXXX)
  ERR_FILE=$(mktemp /tmp/${DOMAIN}-fetch-error.XXXXXX)

  if command -v curl >/dev/null 2>&1; then
    curl -fsS "$url" >"$RESP_FILE" 2>"$ERR_FILE"
    return $?
  fi

  if command -v wget >/dev/null 2>&1; then
    wget -qO- "$url" >"$RESP_FILE" 2>"$ERR_FILE"
    return $?
  fi

  echo "Neither curl nor wget is available" >"$ERR_FILE"
  return 127
}

read_json_path() {
  local file_path="$1"
  local key_path="$2"
  local value

  value=$(jct "$file_path" get "$key_path" 2>/dev/null)
  [ "$value" = "null" ] && value=""
  printf '%s' "$value"
}

sanitize_peer_name() {
  case "$1" in
    ''|*[!A-Za-z0-9_-]*) return 1 ;;
    *) return 0 ;;
  esac
}

handle_provision_import() {
  local provision_url provision_token provision_peer fetch_url separator
  local address allowed dns endpoint keepalive mtu peerpsk peerpub port privkey

  provision_url=$(jct "$REQ_FILE" get provision_url 2>/dev/null)
  [ "$provision_url" = "null" ] && provision_url=""
  provision_token=$(jct "$REQ_FILE" get provision_token 2>/dev/null)
  [ "$provision_token" = "null" ] && provision_token=""
  provision_peer=$(jct "$REQ_FILE" get provision_peer 2>/dev/null)
  [ "$provision_peer" = "null" ] && provision_peer=""

  [ -n "$provision_url" ] || json_error 422 "Provisioner URL is required" "422 Unprocessable Entity"
  [ -n "$provision_peer" ] || json_error 422 "Provision peer name is required" "422 Unprocessable Entity"
  sanitize_peer_name "$provision_peer" || json_error 422 "Provision peer name contains invalid characters" "422 Unprocessable Entity"

  fetch_url="${provision_url%/}/$provision_peer"
  separator='?'
  case "$fetch_url" in
    *\?*) separator='&' ;;
  esac
  fetch_url="$fetch_url${separator}create=1"
  if [ -n "$provision_token" ]; then
    separator='&'
    case "$fetch_url" in
      *\?*) separator='&' ;;
    esac
    fetch_url="$fetch_url${separator}token=$provision_token"
  fi

  http_fetch "$fetch_url" || json_error 502 "Failed to fetch a WireGuard profile from the provisioner" "502 Bad Gateway"

  [ "$(read_json_path "$RESP_FILE" status)" = "ok" ] || {
    message=$(read_json_path "$RESP_FILE" error)
    [ -n "$message" ] || message="Provisioner returned an invalid WireGuard profile"
    json_error 502 "$message" "502 Bad Gateway"
  }

  address=$(read_json_path "$RESP_FILE" data.address)
  privkey=$(read_json_path "$RESP_FILE" data.privkey)
  dns=$(read_json_path "$RESP_FILE" data.dns)
  endpoint=$(read_json_path "$RESP_FILE" data.endpoint)
  peerpub=$(read_json_path "$RESP_FILE" data.peerpub)
  peerpsk=$(read_json_path "$RESP_FILE" data.peerpsk)
  allowed=$(read_json_path "$RESP_FILE" data.allowed)
  port=$(read_json_path "$RESP_FILE" data.port)
  keepalive=$(read_json_path "$RESP_FILE" data.keepalive)
  mtu=$(read_json_path "$RESP_FILE" data.mtu)

  [ -n "$address" ] || json_error 502 "Provisioner did not return a WireGuard address" "502 Bad Gateway"
  [ -n "$privkey" ] || json_error 502 "Provisioner did not return a WireGuard private key" "502 Bad Gateway"
  [ -n "$endpoint" ] || json_error 502 "Provisioner did not return a WireGuard endpoint" "502 Bad Gateway"
  [ -n "$peerpub" ] || json_error 502 "Provisioner did not return a peer public key" "502 Bad Gateway"

  enabled=true
  [ -n "$keepalive" ] || keepalive=25
  provision_url="$provision_url"
  provision_token="$provision_token"
  provision_peer="$provision_peer"

  write_config
  send_json '{"status":"ok","message":"WireGuard profile imported from provisioner"}'
}

write_config() {
  ensure_config
  TMP_FILE=$(mktemp /tmp/${DOMAIN}.XXXXXX)
  echo '{}' >"$TMP_FILE"
  jct "$TMP_FILE" set "$DOMAIN.enabled" "$enabled" >/dev/null 2>&1
  jct "$TMP_FILE" set "$DOMAIN.address" "$address" >/dev/null 2>&1
  jct "$TMP_FILE" set "$DOMAIN.allowed" "$allowed" >/dev/null 2>&1
  jct "$TMP_FILE" set "$DOMAIN.dns" "$dns" >/dev/null 2>&1
  jct "$TMP_FILE" set "$DOMAIN.endpoint" "$endpoint" >/dev/null 2>&1
  jct "$TMP_FILE" set "$DOMAIN.keepalive" "$keepalive" >/dev/null 2>&1
  jct "$TMP_FILE" set "$DOMAIN.mtu" "$mtu" >/dev/null 2>&1
  jct "$TMP_FILE" set "$DOMAIN.peerpsk" "$peerpsk" >/dev/null 2>&1
  jct "$TMP_FILE" set "$DOMAIN.peerpub" "$peerpub" >/dev/null 2>&1
  jct "$TMP_FILE" set "$DOMAIN.port" "$port" >/dev/null 2>&1
  jct "$TMP_FILE" set "$DOMAIN.privkey" "$privkey" >/dev/null 2>&1
  jct "$TMP_FILE" set "$DOMAIN.provision_url" "$provision_url" >/dev/null 2>&1
  jct "$TMP_FILE" set "$DOMAIN.provision_token" "$provision_token" >/dev/null 2>&1
  jct "$TMP_FILE" set "$DOMAIN.provision_peer" "$provision_peer" >/dev/null 2>&1
  jct "$CONFIG_FILE" import "$TMP_FILE" >/dev/null 2>&1
}

read_body() {
  REQ_FILE=$(mktemp /tmp/${DOMAIN}-req.XXXXXX)
  if [ -n "$CONTENT_LENGTH" ]; then
    dd bs=1 count="$CONTENT_LENGTH" 2>/dev/null >"$REQ_FILE"
  else
    cat >"$REQ_FILE"
  fi
}

normalize_bool() {
  case "$(printf '%s' "$1" | tr 'A-Z' 'a-z')" in
    1|true|yes|on) printf 'true' ;;
    0|false|no|off|""|null) printf 'false' ;;
    *) json_error 422 "Invalid boolean value" "422 Unprocessable Entity" ;;
  esac
}

handle_get() {
  local payload wg_status supported localpub
  payload=$(read_domain_json)
  wg_status=0
  is_wg_up && wg_status=1
  payload=$(append_json_field "$payload" "wg_status" "$wg_status" raw)
  supported=$(wg_supported && echo true || echo false)
  payload=$(append_json_field "$payload" "wg_supported" "$supported" raw)
  localpub=$(derive_public_key "$(jct "$CONFIG_FILE" get "$DOMAIN.privkey" 2>/dev/null)")
  payload=$(append_json_field "$payload" "localpub" "$localpub")
  printf '%s' "$payload"
}

handle_derive_pubkey() {
  local privkey localpub

  wg_supported || json_error 503 "WireGuard tooling is not available" "503 Service Unavailable"

  privkey=$(jct "$REQ_FILE" get privkey 2>/dev/null)
  [ -n "$privkey" ] || json_error 400 "Missing privkey field" "400 Bad Request"

  localpub=$(derive_public_key "$privkey")
  [ -n "$localpub" ] || json_error 400 "Failed to derive public key from provided private key" "400 Bad Request"

  send_json "{\"status\":\"ok\",\"data\":{\"localpub\":\"$localpub\"}}"
}

handle_generate_keypair() {
  local privkey localpub payload

  wg_supported || json_error 503 "WireGuard tooling is not available" "503 Service Unavailable"

  privkey=$(generate_private_key)
  [ -n "$privkey" ] || json_error 500 "Failed to generate WireGuard private key" "500 Internal Server Error"

  localpub=$(derive_public_key "$privkey")
  [ -n "$localpub" ] || json_error 500 "Failed to derive WireGuard public key" "500 Internal Server Error"

  payload='{}'
  payload=$(append_json_field "$payload" "privkey" "$privkey")
  payload=$(append_json_field "$payload" "localpub" "$localpub")
  send_json "{\"status\":\"ok\",\"message\":\"WireGuard key pair generated\",\"data\":$payload}"
}

handle_generate_psk() {
  local peerpsk payload

  wg_supported || json_error 503 "WireGuard tooling is not available" "503 Service Unavailable"

  peerpsk=$(generate_preshared_key)
  [ -n "$peerpsk" ] || json_error 500 "Failed to generate WireGuard pre-shared key" "500 Internal Server Error"

  payload='{}'
  payload=$(append_json_field "$payload" "peerpsk" "$peerpsk")
  send_json "{\"status\":\"ok\",\"message\":\"WireGuard pre-shared key generated\",\"data\":$payload}"
}

handle_post() {
  local action

  read_body

  action=$(jct "$REQ_FILE" get action 2>/dev/null)
  case "$action" in
    derive_pubkey)
      handle_derive_pubkey
      ;;
    generate_keypair)
      handle_generate_keypair
      ;;
    generate_psk)
      handle_generate_psk
      ;;
    provision_import)
      handle_provision_import
      ;;
  esac

  enabled=$(normalize_bool "$(jct "$REQ_FILE" get enabled 2>/dev/null)")
  address=$(jct "$REQ_FILE" get address 2>/dev/null)
  allowed=$(jct "$REQ_FILE" get allowed 2>/dev/null)
  dns=$(jct "$REQ_FILE" get dns 2>/dev/null)
  endpoint=$(jct "$REQ_FILE" get endpoint 2>/dev/null)
  provision_url=$(jct "$REQ_FILE" get provision_url 2>/dev/null)
  provision_peer=$(jct "$REQ_FILE" get provision_peer 2>/dev/null)
  provision_token=$(jct "$REQ_FILE" get provision_token 2>/dev/null)
  keepalive=$(jct "$REQ_FILE" get keepalive 2>/dev/null)
  mtu=$(jct "$REQ_FILE" get mtu 2>/dev/null)
  peerpsk=$(jct "$REQ_FILE" get peerpsk 2>/dev/null)
  peerpub=$(jct "$REQ_FILE" get peerpub 2>/dev/null)
  port=$(jct "$REQ_FILE" get port 2>/dev/null)
  privkey=$(jct "$REQ_FILE" get privkey 2>/dev/null)

  write_config

  send_json '{"status":"ok","message":"WireGuard configuration saved"}'
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
