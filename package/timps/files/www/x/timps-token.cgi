#!/bin/sh
# Hand the per-boot timps /control token to the authenticated WebUI session.
# timps writes a fresh random token to /run/timps.token (0640) on every start;
# with it a browser page can drive timps DIRECTLY (no local bridge CGI):
#   const {token, port} = await (await fetch('/x/timps-token.cgi')).json();
#   fetch(`http://${location.hostname}:${port}/control`, {method:'POST',
#         headers:{'X-Timps-Token': token}, body:'{"image":{...}}'});
# Only the per-boot token is exposed here - a configured http.token secret
# never reaches the file (timps keeps it in memory only).

# Check authentication
. /var/www/x/auth.sh
require_auth

CONF="/etc/timps.conf"
TOKEN_FILE="/run/timps.token"

# honor a custom http.token_file / http.port from the timps config
tf=$(sed -n 's/^[[:space:]]*http\.token_file[[:space:]]*=[[:space:]]*"\{0,1\}\([^"#]*\).*/\1/p' "$CONF" 2>/dev/null | head -n1 | tr -d ' \t')
[ -n "$tf" ] && TOKEN_FILE="$tf"
port=$(sed -n 's/^[[:space:]]*http\.port[[:space:]]*=[[:space:]]*\([0-9]\{1,\}\).*/\1/p' "$CONF" 2>/dev/null | head -n1)
[ -z "$port" ] && port=8880
# whether timps serves the HTTP port over TLS (http.https): the browser must
# then use https:// for the media/control URLs.
https=$(sed -n 's/^[[:space:]]*http\.https[[:space:]]*=[[:space:]]*\([0-9A-Za-z]*\).*/\1/p' "$CONF" 2>/dev/null | head -n1)
case "$https" in 1 | true | yes | on) tls=true ;; *) tls=false ;; esac

echo "Content-Type: application/json"
echo "Cache-Control: no-store"
echo "Connection: close"
echo

token=""
[ -r "$TOKEN_FILE" ] && token=$(head -n1 "$TOKEN_FILE" 2>/dev/null | tr -cd '0-9A-Za-z')

if [ -n "$token" ]; then
	printf '{"token":"%s","port":%s,"tls":%s}\n' "$token" "$port" "$tls"
else
	printf '{"error":"no token available","port":%s,"tls":%s}\n' "$port" "$tls"
fi
