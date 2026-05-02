#!/bin/sh

. /var/www/x/auth.sh
require_auth

THINGINO_CONFIG="${THINGINO_CONFIG:-/etc/thingino.json}"

read_agent_config() {
	key=$1
	if command -v jct >/dev/null 2>&1 && [ -f "$THINGINO_CONFIG" ]; then
		jct "$THINGINO_CONFIG" get "$key" 2>/dev/null | tr -d '\n'
	fi
}

read_agent_config_text() {
	read_agent_config "$1" | tr -d '"'
}

agent_listener_port() {
	port=$(read_agent_config_text agent.port)
	case "$port" in
		'' | *[!0-9]*) port=1998 ;;
		0) port=1998 ;;
	esac
	printf '%s' "$port"
}

agent_backend_port() {
	port=$(agent_listener_port)
	if [ "$port" -le 64535 ]; then
		printf '%s' $((port + 1000))
	else
		printf '%s' $((port - 1))
	fi
}

agent_base_url() {
	configured=${AGENT_BASE_URL:-}
	if [ -n "$configured" ]; then
		printf '%s' "$configured"
		return 0
	fi
	if [ "true" = "$(read_agent_config agent.tls)" ]; then
		printf 'http://127.0.0.1:%s' "$(agent_backend_port)"
	else
		printf 'http://127.0.0.1:%s' "$(agent_listener_port)"
	fi
}

agent_request_urls() {
	if [ "true" = "$(read_agent_config agent.tls)" ]; then
		printf 'http://127.0.0.1:%s\n' "$(agent_backend_port)"
		printf 'https://127.0.0.1:%s\n' "$(agent_listener_port)"
	else
		printf 'http://127.0.0.1:%s\n' "$(agent_listener_port)"
	fi
}

agent_auth_header() {
	token=$(read_agent_config_text agent.token)
	[ -n "$token" ] || return 1
	printf 'Authorization: Bearer %s' "$token"
}

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

strip_query_param() {
	key=$1
	query=$2
	result=
	old_ifs=$IFS
	IFS='&'
	for pair in $query; do
		name=${pair%%=*}
		[ -n "$name" ] || continue
		[ "$name" = "$key" ] && continue
		if [ -n "$result" ]; then
			result="$result&$pair"
		else
			result=$pair
		fi
	done
	IFS=$old_ifs
	printf '%s' "$result"
}

extract_request_uri_path() {
	request_uri=$1
	request_path=${request_uri%%\?*}
	case "$request_path" in
		*/x/agent.cgi/*)
			printf '%s' "${request_path#*/x/agent.cgi}"
			return 0
			;;
	esac
	return 1
}

is_event_stream_request() {
	case "$TARGET_PATH" in
		/api/v1/events | /api/v1/events/*)
			return 0
			;;
	esac
	return 1
}

send_status() {
	status_line=$1
	content_type=$2
	printf 'Status: %s\r\n' "$status_line"
	printf 'Content-Type: %s\r\n' "$content_type"
	printf 'Cache-Control: no-store\r\n'
	printf 'Pragma: no-cache\r\n'
	printf 'Connection: close\r\n'
	printf '\r\n'
}

json_error() {
	status_line=${1:-502 Bad Gateway}
	message=$2
	send_status "$status_line" 'application/json'
	printf '{"error":{"message":"%s"}}\n' "$(printf '%s' "$message" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\r/\\r/g' -e ':a;N;$!ba;s/\n/\\n/g')"
	exit 0
}

TARGET_PATH=${PATH_INFO:-}
case "$TARGET_PATH" in
	/api/v1 | /api/v1/*) ;;
	*) TARGET_PATH= ;;
esac
[ -n "$TARGET_PATH" ] || TARGET_PATH=$(extract_query_param agent_path "${QUERY_STRING:-}")
[ -n "$TARGET_PATH" ] || TARGET_PATH=$(extract_request_uri_path "${REQUEST_URI:-}")
[ -n "$TARGET_PATH" ] || json_error '400 Bad Request' 'Missing agent path.'

TARGET_URL_BASE="$(agent_base_url)"
FORWARD_QUERY=$(strip_query_param agent_path "${QUERY_STRING:-}")
if [ -n "$FORWARD_QUERY" ]; then
	TARGET_URL_BASE="$TARGET_URL_BASE?$FORWARD_QUERY"
fi

if [ "${REQUEST_METHOD:-GET}" = GET ] && is_event_stream_request; then
	send_status '200 OK' 'text/event-stream'
	auth_header=$(agent_auth_header || true)
	if [ -n "$HTTP_ACCEPT" ]; then
		if [ -n "$auth_header" ]; then
			exec curl -sS -N -H "$auth_header" -H "Accept: $HTTP_ACCEPT" "$TARGET_URL_BASE"
		else
			exec curl -sS -N -H "Accept: $HTTP_ACCEPT" "$TARGET_URL_BASE"
		fi
	else
		if [ -n "$auth_header" ]; then
			exec curl -sS -N -H "$auth_header" -H 'Accept: text/event-stream' "$TARGET_URL_BASE"
		else
			exec curl -sS -N -H 'Accept: text/event-stream' "$TARGET_URL_BASE"
		fi
	fi
fi

BODY_FILE=
if [ -n "$CONTENT_LENGTH" ] && [ "$CONTENT_LENGTH" -gt 0 ] 2>/dev/null; then
	BODY_FILE=$(mktemp /tmp/agent-cgi-body.XXXXXX) || json_error '500 Internal Server Error' 'Unable to create temporary body file.'
	dd bs=1 count="$CONTENT_LENGTH" of="$BODY_FILE" 2>/dev/null || {
		rm -f "$BODY_FILE"
		json_error '500 Internal Server Error' 'Unable to read request body.'
	}
fi

HEADERS_FILE=$(mktemp /tmp/agent-cgi-headers.XXXXXX) || {
	rm -f "$BODY_FILE"
	json_error '500 Internal Server Error' 'Unable to create temporary header file.'
}
BODY_OUT=$(mktemp /tmp/agent-cgi-out.XXXXXX) || {
	rm -f "$BODY_FILE" "$HEADERS_FILE"
	json_error '500 Internal Server Error' 'Unable to create temporary response file.'
}

set -- -sS -D "$HEADERS_FILE" -o "$BODY_OUT" -X "${REQUEST_METHOD:-GET}"
if [ -n "$CONTENT_TYPE" ]; then
	set -- "$@" -H "Content-Type:$CONTENT_TYPE"
fi
if [ -n "$HTTP_ACCEPT" ]; then
	set -- "$@" -H "Accept:$HTTP_ACCEPT"
fi
auth_header=$(agent_auth_header || true)
if [ -n "$auth_header" ]; then
	set -- "$@" -H "$auth_header"
fi
if [ -n "$BODY_FILE" ]; then
	set -- "$@" --data-binary "@$BODY_FILE"
fi

curl_failed=1
for candidate in $(agent_request_urls); do
	TARGET_URL="$candidate$TARGET_PATH"
	if [ -n "$FORWARD_QUERY" ]; then
		TARGET_URL="$TARGET_URL?$FORWARD_QUERY"
	fi
	insecure_flag=""
	case "$candidate" in
		https://*) insecure_flag='-k' ;;
	esac
	if [ -n "$insecure_flag" ]; then
		if curl "$@" "$insecure_flag" "$TARGET_URL"; then
			curl_failed=0
			break
		fi
	else
		if curl "$@" "$TARGET_URL"; then
			curl_failed=0
			break
		fi
	fi
done
if [ "$curl_failed" -ne 0 ]; then
	rm -f "$BODY_FILE" "$HEADERS_FILE" "$BODY_OUT"
	json_error '502 Bad Gateway' 'Camera agent request failed.'
fi

STATUS_LINE=$(awk 'toupper($1) ~ /^HTTP\// { code=$2; text=$3; for (i = 4; i <= NF; i++) text = text " " $i } END { if (code == "") code=502; if (text == "") text="Bad Gateway"; printf "%s %s", code, text }' "$HEADERS_FILE")
CONTENT_TYPE=$(awk 'BEGIN { IGNORECASE=1 } /^Content-Type:/ { sub(/^Content-Type:[[:space:]]*/, "", $0); sub(/\r$/, "", $0); print; exit }' "$HEADERS_FILE")
[ -n "$CONTENT_TYPE" ] || CONTENT_TYPE='application/json'

send_status "$STATUS_LINE" "$CONTENT_TYPE"
cat "$BODY_OUT"

rm -f "$BODY_FILE" "$HEADERS_FILE" "$BODY_OUT"
