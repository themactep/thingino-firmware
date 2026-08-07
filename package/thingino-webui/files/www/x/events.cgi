#!/bin/sh
# BusyBox httpd CGI for server-sent events (SSE)

# Check authentication
. /var/www/x/auth.sh
require_auth

printf "Cache-Control: no-cache\r\n"
printf "Content-Type: text/event-stream\r\n"
printf "\r\n"

# Prefer camera-agent events; fall back to prudyntctl when present.
if command -v curl >/dev/null 2>&1; then
	port=1998
	if command -v jct >/dev/null 2>&1 && [ -f /etc/thingino.json ]; then
		p=$(jct /etc/thingino.json get agent.port 2>/dev/null | tr -d '"')
		case "$p" in
			'' | *[!0-9]*) ;;
			*) port=$p ;;
		esac
	fi
	if curl -sS --max-time 1 "http://127.0.0.1:${port}/api/v1/device" >/dev/null 2>&1; then
		exec curl -sS -N "http://127.0.0.1:${port}/api/v1/events"
	fi
fi

if command -v prudyntctl >/dev/null 2>&1; then
	prudyntctl events | sed -u 's/^/data: /' | while IFS= read -r line; do
		echo "$line"
		echo
	done
	exit 0
fi

printf 'data: {"error":"no event backend available"}\n\n'
