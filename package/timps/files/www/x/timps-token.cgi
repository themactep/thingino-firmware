#!/bin/sh
# shellcheck disable=SC1091
# Hand the per-boot timps /control token to the authenticated WebUI session.
# timps writes a fresh random token to /run/timps.token (0640) on every start;
# with it a browser page can drive timps DIRECTLY (no local bridge CGI):
#   const {token, port, scheme} = await (await fetch('/x/timps-token.cgi')).json();
#   const s = scheme === 'both' ? location.protocol.replace(':','') : scheme;
#   fetch(`${s}://${location.hostname}:${port}/control`, {method:'POST',
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
# http.https is a TRI-STATE since timps v1.9.11, not a boolean:
#   0  plaintext only                      -> scheme "http"
#   1  http AND https on the SAME port, picked per connection by a first-byte
#      peek (true/yes/on parse as 1)        -> scheme "both"
#   2  TLS only, plaintext gets a 426       -> scheme "https"
#
# "scheme" is the field the WebUI JS should use. On "both" it must follow the
# PAGE's own protocol rather than a fixed guess: an https:// WebUI page may not
# fetch an http:// subresource (mixed content), and an http:// page hitting
# https:// dies on the self-signed cert with no possible interstitial. Since
# timps answers either scheme on that one port, following the page always works.
#
# "tls" is kept for JS that predates "scheme" (a cached page, a partial
# upgrade): true for either on-value, i.e. the old "use https://" meaning.
https=$(sed -n 's/^[[:space:]]*http\.https[[:space:]]*=[[:space:]]*\([0-9A-Za-z]*\).*/\1/p' "$CONF" 2>/dev/null | head -n1 | tr '[:upper:]' '[:lower:]')
case "$https" in
	1 | true | yes | on)
		scheme=both
		tls=true
		;;
	2)
		scheme=https
		tls=true
		;;
	*)
		scheme=http
		tls=false
		;;
esac

echo "Content-Type: application/json"
echo "Cache-Control: no-store"
echo "Connection: close"
echo

token=""
[ -r "$TOKEN_FILE" ] && token=$(head -n1 "$TOKEN_FILE" 2>/dev/null | tr -cd '0-9A-Za-z')

if [ -n "$token" ]; then
	printf '{"token":"%s","port":%s,"tls":%s,"scheme":"%s"}\n' "$token" "$port" "$tls" "$scheme"
else
	printf '{"error":"no token available","port":%s,"tls":%s,"scheme":"%s"}\n' "$port" "$tls" "$scheme"
fi
