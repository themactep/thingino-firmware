#!/bin/sh
# shellcheck disable=SC1091
# Same-origin fMP4 stream proxy. A browser will not fetch
# http://<host>:8080/chN.mp4 from an HTTPS page (mixed content), so stream it
# through uhttpd instead. Query: ch=0|1.

. /var/www/x/auth.sh
require_auth

CHANNEL=1
OLD_IFS=$IFS
IFS='&'
for kv in $QUERY_STRING; do
	case "$kv" in
		ch=0 | ch=1) CHANNEL=${kv#ch=} ;;
	esac
done
IFS=$OLD_IFS

API_KEY_FILE="/etc/thingino-api.key"
URL="http://127.0.0.1:8080/ch${CHANNEL}.mp4"
if [ -r "$API_KEY_FILE" ]; then
	TOKEN=$(tr -d '\n\r ' <"$API_KEY_FILE")
	[ -n "$TOKEN" ] && URL="$URL?token=$TOKEN"
fi

printf 'Content-Type: video/mp4\r\n'
printf 'Cache-Control: no-store\r\n'
printf '\r\n'
exec curl -sS -N "$URL"
