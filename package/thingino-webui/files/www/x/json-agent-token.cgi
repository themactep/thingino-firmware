#!/bin/sh

. /var/www/x/auth.sh
require_auth

THINGINO_CONFIG="${THINGINO_CONFIG:-/etc/thingino.json}"

send_json() {
  status="${2:-200 OK}"
  printf "Status: %s\r\n" "$status"
  printf "Content-Type: application/json\r\n"
  printf "Cache-Control: no-store\r\n"
  printf "Pragma: no-cache\r\n"
  printf "Connection: close\r\n"
  printf "\r\n"
  printf "%s\n" "$1"
  exit 0
}

json_error() {
  code="${1:-500}"
  message="$2"
  send_json "{\"ok\":false,\"error\":{\"code\":$code,\"message\":\"$message\"}}" "500 Internal Server Error"
}

token=$(jct "$THINGINO_CONFIG" get agent.token 2>/dev/null | tr -d '"\n\r')
if [ -z "$token" ]; then
  json_error 503 "Agent token not configured"
fi

printf "Content-Type: application/json\r\n"
printf "Cache-Control: no-store\r\n"
printf "Pragma: no-cache\r\n"
printf "Connection: close\r\n"
printf "\r\n"
printf '{"ok":true,"api_token":"%s"}\n' "$token"
