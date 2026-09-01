#!/bin/sh
# shellcheck disable=SC1091
#
# Hand the WebUI page the credential for motors-daemon's WebSocket listener.
#
# The listener requires a token from any non-loopback peer, and the browser IS
# a non-loopback peer even when it loaded the page from this same camera - so
# the PTZ panel cannot connect without one. The per-boot token lives in a
# mode-0640 root-owned file that the page has no way to read; this CGI is the
# bridge, and it is protected by the same WebUI session auth as every other
# endpoint here.
#
# Only the per-boot token is ever exposed. A persistent motors.ws_token
# secret from the config file never reaches a file at all - the daemon hashes
# it at startup and wipes the plaintext - so there is nothing here that could
# leak it.
#
# Deliberately modelled on timps's /x/timps-token.cgi rather than invented:
# same problem, same deployment, and the WebUI already has one working shape
# for it.

# Check authentication
. /var/www/x/auth.sh
require_auth

CONFIG="/etc/thingino.json"
TOKEN_FILE="/run/motors.token"
DEFAULT_PORT=8089

# Honour a relocated token file / non-default port, matching what
# load_ws_config_file() in motors-daemon reads.
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

# marker file the daemon writes once a cert actually loads (not re-derived
# from config here, to avoid a second copy of that resolution disagreeing)
tls=false
[ -e /run/motors.tls ] && tls=true

printf 'Status: 200 OK\r\n'
printf 'Content-Type: application/json\r\n'
printf 'Cache-Control: no-store\r\n'
printf 'Connection: close\r\n'
printf '\r\n'

# head -n1 + tr: the token is 32 hex characters and nothing else. Stripping
# everything outside that set is what makes it safe to interpolate into the
# hand-built JSON below without an escaper, the same way timps-token.cgi does
# it - a token file that somehow contained a quote or a newline can then only
# produce a short/empty token, never a malformed document.
token=""
[ -r "$TOKEN_FILE" ] && token=$(head -n1 "$TOKEN_FILE" 2>/dev/null | tr -cd '0-9A-Za-z')

if [ -n "$token" ]; then
	printf '{"token":"%s","port":%s,"enabled":%s,"tls":%s}\n' \
		"$token" "$port" "$enabled" "$tls"
else
	# Not an HTTP error: "the listener is not usable right now" is a normal
	# answer (ws_enabled=false, or the daemon refused to mint a token) and
	# the page's job is to fall back to the CGI path, not to show an error.
	printf '{"error":"no token available","port":%s,"enabled":false}\n' "$port"
fi
