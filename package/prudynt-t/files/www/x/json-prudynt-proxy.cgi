#!/bin/sh
# shellcheck disable=SC1091
# Same-origin reverse proxy to the prudynt HTTP API on localhost. WebUI pages
# cannot reach http://<host>:8080 directly: on an HTTPS page the browser blocks
# it as mixed content, so config reads and saves silently fail.

. /var/www/x/auth.sh
require_auth

UPSTREAM="http://127.0.0.1:8080"

url_decode() {
	value="$(echo "$1" | sed 's/+/ /g')"
	printf '%b' "$(echo "$value" | sed 's/%/\\x/g')"
}

extract_query_param() {
	key=$1
	query=$2
	old_ifs=$IFS
	IFS='&'
	for pair in $query; do
		name=${pair%%=*}
		value=${pair#*=}
		[ "$name" = "$key" ] || continue
		url_decode "$value"
		IFS=$old_ifs
		return 0
	done
	IFS=$old_ifs
	return 1
}

send_error() {
	status_line=${1:-502 Bad Gateway}
	message=$2
	printf 'Status: %s\r\n' "$status_line"
	printf 'Content-Type: application/json\r\n'
	printf 'Cache-Control: no-store\r\n'
	printf 'Connection: close\r\n'
	printf '\r\n'
	printf '{"error":{"message":"%s"}}\n' "$(printf '%s' "$message" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"
	exit 0
}

TARGET_PATH=$(extract_query_param upstream_path "${QUERY_STRING:-}") || TARGET_PATH=""
case "$TARGET_PATH" in
	/api/v1/*) ;;
	*) send_error '400 Bad Request' 'Missing or invalid upstream path.' ;;
esac

TARGET_URL="$UPSTREAM$TARGET_PATH"

BODY_FILE=
if [ -n "$CONTENT_LENGTH" ] && [ "$CONTENT_LENGTH" -gt 0 ] 2>/dev/null; then
	BODY_FILE=$(mktemp /tmp/prudynt-proxy-body.XXXXXX) || send_error '500 Internal Server Error' 'Unable to create temporary body file.'
	dd bs=1 count="$CONTENT_LENGTH" of="$BODY_FILE" 2>/dev/null || {
		rm -f "$BODY_FILE"
		send_error '500 Internal Server Error' 'Unable to read request body.'
	}
fi

HEADERS_FILE=$(mktemp /tmp/prudynt-proxy-headers.XXXXXX) || {
	rm -f "$BODY_FILE"
	send_error '500 Internal Server Error' 'Unable to create temporary header file.'
}
BODY_OUT=$(mktemp /tmp/prudynt-proxy-out.XXXXXX) || {
	rm -f "$BODY_FILE" "$HEADERS_FILE"
	send_error '500 Internal Server Error' 'Unable to create temporary response file.'
}

set -- -sS -D "$HEADERS_FILE" -o "$BODY_OUT" -X "${REQUEST_METHOD:-GET}"
[ -n "$CONTENT_TYPE" ] && set -- "$@" -H "Content-Type:$CONTENT_TYPE"
[ -n "$HTTP_ACCEPT" ] && set -- "$@" -H "Accept:$HTTP_ACCEPT"
[ -n "$HTTP_X_API_KEY" ] && set -- "$@" -H "X-API-Key:$HTTP_X_API_KEY"
[ -n "$BODY_FILE" ] && set -- "$@" --data-binary "@$BODY_FILE"

if ! curl "$@" "$TARGET_URL"; then
	rm -f "$BODY_FILE" "$HEADERS_FILE" "$BODY_OUT"
	send_error '502 Bad Gateway' 'Prudynt request failed.'
fi

STATUS_LINE=$(awk 'toupper($1) ~ /^HTTP\// { code=$2; text=$3; for (i = 4; i <= NF; i++) text = text " " $i } END { if (code == "") code=502; if (text == "") text="Bad Gateway"; printf "%s %s", code, text }' "$HEADERS_FILE")
CONTENT_TYPE=$(awk 'BEGIN { IGNORECASE=1 } /^Content-Type:/ { sub(/^Content-Type:[[:space:]]*/, "", $0); sub(/\r$/, "", $0); print; exit }' "$HEADERS_FILE")
[ -n "$CONTENT_TYPE" ] || CONTENT_TYPE='application/json'

printf 'Status: %s\r\n' "$STATUS_LINE"
printf 'Content-Type: %s\r\n' "$CONTENT_TYPE"
printf 'Cache-Control: no-store\r\n'
printf 'Connection: close\r\n'
printf '\r\n'
cat "$BODY_OUT"

rm -f "$BODY_FILE" "$HEADERS_FILE" "$BODY_OUT"
