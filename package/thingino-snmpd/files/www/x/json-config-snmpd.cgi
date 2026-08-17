#!/bin/sh
# shellcheck disable=SC1091,SC2018,SC2019,SC2329

# Check authentication
. /var/www/x/auth.sh
require_auth

DOMAIN="snmpd"
CONFIG_FILE="/etc/thingino.json"
DEFAULTS_FILE="/usr/share/thingino-defaults/50-snmpd.json"
DAEMON="mini-snmpd"
INIT_SCRIPT="/etc/init.d/S60snmpd"
TMP_FILE=""
REQ_FILE=""

cleanup() {
	[ -n "$TMP_FILE" ] && rm -f "$TMP_FILE"
	[ -n "$REQ_FILE" ] && rm -f "$REQ_FILE"
}
trap cleanup EXIT

json_escape() {
	printf '%s' "$1" | tr -d '\n\r' | sed \
		-e 's/\\/\\\\/g' \
		-e 's/"/\\"/g'
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
	case "$1" in
		"" | null) printf '' ;;
		*) printf '%s' "$1" | sed -e 's/^"//' -e 's/"$//' -e 's/^\\"//' -e 's/\\"$//' ;;
	esac
}

normalize_bool() {
	case "$(printf '%s' "$1" | tr 'A-Z' 'a-z')" in
		1 | true | yes | on) printf 'true' ;;
		0 | false | no | off | "" | null) printf 'false' ;;
		*) json_error 422 "Invalid boolean value" "422 Unprocessable Entity" ;;
	esac
}

is_number() {
	case "$1" in
		'' | *[!0-9]*) return 1 ;;
		*) return 0 ;;
	esac
}

get_value() {
	jct "$CONFIG_FILE" get "$DOMAIN.$1" 2>/dev/null | tr -d '\n'
}

get_text() {
	strip_json_string "$(get_value "$1")"
}

req_value() {
	jct "$REQ_FILE" get "$1" 2>/dev/null | tr -d '\n'
}

req_text() {
	strip_json_string "$(req_value "$1")"
}

set_value() {
	jct "$TMP_FILE" set "$DOMAIN.$1" "$2" >/dev/null 2>&1
}

ensure_config() {
	if [ ! -f "$CONFIG_FILE" ]; then
		umask 077
		echo '{}' >"$CONFIG_FILE"
	fi

	# A bundle install drops the shipped defaults on disk but cannot merge
	# them into thingino.json the way thingino-core does at build time.
	if [ -z "$(jct "$CONFIG_FILE" get "$DOMAIN" 2>/dev/null | tr -d '\n')" ] &&
		[ -f "$DEFAULTS_FILE" ]; then
		jct "$CONFIG_FILE" import "$DEFAULTS_FILE" >/dev/null 2>&1
	fi
}

read_body() {
	REQ_FILE=$(mktemp /tmp/${DOMAIN}-req.XXXXXX)
	if [ -n "$CONTENT_LENGTH" ]; then
		dd bs=1 count="$CONTENT_LENGTH" 2>/dev/null >"$REQ_FILE"
	else
		cat >"$REQ_FILE"
	fi
}

handle_get() {
	ensure_config

	enabled=$(get_value enabled)
	auth=$(get_value auth)
	[ "true" = "$enabled" ] || enabled="false"
	[ "true" = "$auth" ] || auth="false"

	port=$(get_text port)
	is_number "$port" || port=161
	timeout=$(get_text timeout)
	is_number "$timeout" || timeout=1

	loglevel=$(get_text loglevel)
	[ -n "$loglevel" ] || loglevel="notice"

	running="false"
	pidof "$DAEMON" >/dev/null 2>&1 && running="true"

	send_json "{
  \"config\": {
    \"enabled\": $enabled,
    \"auth\": $auth,
    \"community\": \"$(json_escape "$(get_text community)")\",
    \"port\": $port,
    \"timeout\": $timeout,
    \"loglevel\": \"$(json_escape "$loglevel")\",
    \"location\": \"$(json_escape "$(get_text location)")\",
    \"contact\": \"$(json_escape "$(get_text contact)")\",
    \"description\": \"$(json_escape "$(get_text description)")\",
    \"listen\": \"$(json_escape "$(get_text listen)")\",
    \"interfaces\": \"$(json_escape "$(get_text interfaces)")\",
    \"disks\": \"$(json_escape "$(get_text disks)")\",
    \"traps\": \"$(json_escape "$(get_text traps)")\"
  },
  \"status\": {
    \"running\": $running
  }
}"
}

handle_post() {
	read_body
	ensure_config

	enabled=$(normalize_bool "$(req_value enabled)")
	auth=$(normalize_bool "$(req_value auth)")

	community=$(req_text community)
	port=$(req_text port)
	timeout=$(req_text timeout)
	loglevel=$(req_text loglevel)
	location=$(req_text location)
	contact=$(req_text contact)
	description=$(req_text description)
	listen=$(req_text listen)
	interfaces=$(req_text interfaces)
	disks=$(req_text disks)
	traps=$(req_text traps)

	# Defaults
	[ -n "$port" ] || port=161
	[ -n "$timeout" ] || timeout=1
	[ -n "$loglevel" ] || loglevel="notice"
	[ -n "$disks" ] || disks="/"

	if ! is_number "$port" || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
		json_error 422 "Port must be between 1 and 65535" "422 Unprocessable Entity"
	fi

	if ! is_number "$timeout" || [ "$timeout" -lt 1 ] || [ "$timeout" -gt 600 ]; then
		json_error 422 "Timeout must be between 1 and 600 seconds" "422 Unprocessable Entity"
	fi

	case "$loglevel" in
		none | err | info | notice | debug) ;;
		*) json_error 422 "Invalid log level" "422 Unprocessable Entity" ;;
	esac

	case "$community" in
		*[!A-Za-z0-9_.-]*) json_error 422 "Community may only contain letters, digits, dot, dash and underscore" "422 Unprocessable Entity" ;;
	esac

	if [ "$enabled" = "true" ] && [ -z "$community" ]; then
		json_error 422 "Community cannot be empty when SNMP is enabled" "422 Unprocessable Entity"
	fi

	TMP_FILE=$(mktemp /tmp/${DOMAIN}.XXXXXX)
	echo '{}' >"$TMP_FILE"

	set_value enabled "$enabled"
	set_value auth "$auth"
	set_value community "$community"
	set_value port "$port"
	set_value timeout "$timeout"
	set_value loglevel "$loglevel"
	set_value location "$location"
	set_value contact "$contact"
	set_value description "$description"
	set_value listen "$listen"
	set_value interfaces "$interfaces"
	set_value disks "$disks"
	set_value traps "$traps"

	jct "$CONFIG_FILE" import "$TMP_FILE" >/dev/null 2>&1
	sync

	# Apply the new settings
	if [ "$enabled" = "true" ]; then
		$INIT_SCRIPT restart >/dev/null 2>&1 &
	else
		$INIT_SCRIPT stop >/dev/null 2>&1 &
	fi

	send_json '{"status":"ok"}'
}

case "$REQUEST_METHOD" in
	GET | "") handle_get ;;
	POST) handle_post ;;
	*) json_error 405 "Method not allowed" "405 Method Not Allowed" ;;
esac
