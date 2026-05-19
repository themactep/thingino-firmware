#!/bin/sh

# Slow heartbeat proxied from Thingino agent

. /var/www/x/auth.sh
require_auth

THINGINO_CONFIG="${THINGINO_CONFIG:-/etc/thingino.json}"

agent_port() {
	port=$(jct "$THINGINO_CONFIG" get agent.port 2>/dev/null | tr -d '\n"')
	case "$port" in
		'' | *[!0-9]*) port=1998 ;;
		0) port=1998 ;;
	esac
	printf '%s' "$port"
}

AGENT_URL="http://127.0.0.1:$(agent_port)"

printf 'Content-Type: application/json\r\n'
printf 'Cache-Control: no-cache\r\n'
printf 'Connection: close\r\n\r\n'

data=$(curl -sS --max-time 2 "$AGENT_URL/api/v1/runtime/heartbeat" 2>/dev/null)
if [ -n "$data" ]; then
	printf '%s\n' "$data"
else
	printf '{}\n'
fi
