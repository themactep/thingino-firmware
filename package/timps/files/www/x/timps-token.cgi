#!/bin/sh
# shellcheck disable=SC1091

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
