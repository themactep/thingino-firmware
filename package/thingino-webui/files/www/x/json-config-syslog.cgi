#!/bin/sh
# shellcheck disable=SC1091,SC2018,SC2019,SC2329,SC3043

# Check authentication
. /var/www/x/auth.sh
require_auth

DOMAIN="rsyslog"
CONFIG_FILE="/etc/thingino.json"
TMP_FILE=""
REQ_FILE=""

cleanup() {
	[ -n "$TMP_FILE" ] && rm -f "$TMP_FILE"
	[ -n "$REQ_FILE" ] && rm -f "$REQ_FILE"
}
trap cleanup EXIT

json_escape() {
	printf '%s' "$1" | sed \
		-e 's/\\/\\\\/g' \
		-e 's/"/\\"/g' \
		-e "s/\r/\\r/g" \
		-e "s/\n/\\n/g"
}

send_json() {
	status="${2:-200 OK}"
	printf 'Status: %s\n' "$status"
	cat <<EOF
Content-Type: application/json
Cache-Control: no-store
Pragma: no-cache
Connection: close

$1
EOF
	exit 0
}

json_error() {
	code="${1:-400}"
	message="$2"
	send_json "{\"error\":{\"code\":$code,\"message\":\"$(json_escape "$message")\"}}" "${3:-400 Bad Request}"
}

strip_json_string() {
	local value
	case "$1" in
		"" | null)
			printf ''
			;;
		*)
			value="$1"
			value=$(printf '%s' "$value" | sed -e 's/^"//' -e 's/"$//' -e 's/^\\"//' -e 's/\\"$//')
			printf '%s' "$value"
			;;
	esac
}

ensure_config() {
	if [ ! -f "$CONFIG_FILE" ]; then
		umask 077
		echo '{}' >"$CONFIG_FILE"
	fi
}

read_domain_json() {
	ensure_config
	local data
	data=$(jct "$CONFIG_FILE" get "$DOMAIN" 2>/dev/null)
	case "$data" in
		"" | null)
			data='{}'
			;;
	esac
	printf '%s' "$data"
}

write_config() {
	ensure_config
	TMP_FILE=$(mktemp /tmp/${DOMAIN}.XXXXXX)
	echo '{}' >"$TMP_FILE"
	jct "$TMP_FILE" set "$DOMAIN.enabled" "$enabled" >/dev/null 2>&1
	jct "$TMP_FILE" set "$DOMAIN.host" "$host" >/dev/null 2>&1
	jct "$TMP_FILE" set "$DOMAIN.port" "$port" >/dev/null 2>&1
	jct "$TMP_FILE" set "$DOMAIN.file" "$file" >/dev/null 2>&1
	jct "$CONFIG_FILE" import "$TMP_FILE" >/dev/null 2>&1
}

read_body() {
	REQ_FILE=$(mktemp /tmp/${DOMAIN}-req.XXXXXX)
	if [ -n "$CONTENT_LENGTH" ]; then
		dd bs=1 count="$CONTENT_LENGTH" 2>/dev/null >"$REQ_FILE"
	else
		cat >"$REQ_FILE"
	fi
}

# The normalize_* functions run inside $( ), where an exit ends only the
# subshell: they return 1 for an invalid value, and the caller answers.
normalize_bool() {
	case "$(printf '%s' "$1" | tr 'A-Z' 'a-z')" in
		1 | true | yes | on) printf 'true' ;;
		0 | false | no | off | "" | null) printf 'false' ;;
		*) return 1 ;;
	esac
}

# The answer for an invalid boolean: call it after ||, never inside $( ).
bad_bool() {
	json_error 422 "Invalid boolean value" "422 Unprocessable Entity"
}

handle_get() {
	send_json "$(read_domain_json)"
}

handle_post() {
	read_body
	new_enabled=$(jct "$REQ_FILE" get enabled 2>/dev/null)
	new_host=$(jct "$REQ_FILE" get host 2>/dev/null)
	new_port=$(jct "$REQ_FILE" get port 2>/dev/null)
	new_file=$(jct "$REQ_FILE" get file 2>/dev/null)

	enabled=$(normalize_bool "$new_enabled") || bad_bool
	file=$(normalize_bool "$new_file") || bad_bool
	host=$(strip_json_string "$new_host")
	port=$(strip_json_string "$new_port")

	[ -n "$port" ] || port="514"

	if [ "$enabled" = "true" ] && [ -z "$host" ]; then
		json_error 422 "Remote host cannot be empty when enabled" "422 Unprocessable Entity"
	fi

	before=$(read_domain_json)
	write_config

	# syslogd takes its remote target from its command line (S01syslogd), so a
	# changed target applies only when it restarts - which also clears the
	# in-memory log (logread). Restart only when the settings really changed.
	if [ "$before" != "$(read_domain_json)" ] && [ -x /etc/init.d/S01syslogd ]; then
		/etc/init.d/S01syslogd restart >/dev/null 2>&1
		send_json '{"status":"ok","message":"Remote logging settings saved and applied. syslogd restarted, so the in-memory log starts over."}'
	fi
	send_json '{"status":"ok","message":"Remote logging settings saved."}'
}

case "$REQUEST_METHOD" in
	GET | "")
		handle_get
		;;
	POST)
		handle_post
		;;
	*)
		json_error 405 "Method not allowed" "405 Method Not Allowed"
		;;
esac
