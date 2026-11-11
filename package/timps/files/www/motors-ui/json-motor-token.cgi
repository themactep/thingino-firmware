#!/bin/sh
# shellcheck disable=SC1091

. /var/www/x/auth.sh
require_auth

CONFIG="/etc/thingino.json"
TOKEN_FILE="/run/motors.token"
DEFAULT_PORT=8089

tf=$(jct "$CONFIG" get motors.ws_token_file 2>/dev/null)
[ -n "$tf" ] && TOKEN_FILE="$tf"

port=$(jct "$CONFIG" get motors.ws_port 2>/dev/null)
case "$port" in
	'' | *[!0-9]*) port="$DEFAULT_PORT" ;;
esac

# ws_enabled defaults to true in the daemon, so only an explicit false counts.
enabled=true
case "$(jct "$CONFIG" get motors.ws_enabled 2>/dev/null)" in
	false | 0 | no | off) enabled=false ;;
esac

tls=false
[ -e /run/motors.tls ] && tls=true

printf 'Status: 200 OK\r\n'
printf 'Content-Type: application/json\r\n'
printf 'Cache-Control: no-store\r\n'
printf 'Connection: close\r\n'
printf '\r\n'

token=""
[ -r "$TOKEN_FILE" ] && token=$(head -n1 "$TOKEN_FILE" 2>/dev/null | tr -cd '0-9A-Za-z')

if [ -n "$token" ]; then
	printf '{"token":"%s","port":%s,"enabled":%s,"tls":%s}\n' \
		"$token" "$port" "$enabled" "$tls"
else
	printf '{"error":"no token available","port":%s,"enabled":false}\n' "$port"
fi
