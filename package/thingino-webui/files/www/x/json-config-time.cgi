#!/bin/sh

# Check authentication
# shellcheck disable=SC1091 # runtime file, not present in the source tree
. /var/www/x/auth.sh
require_auth

: "${NTP_DEFAULT_FILE:=/etc/default/ntp.conf}"
: "${NTP_WORKING_FILE:=/tmp/ntp.conf}"

SYNC_STATUS_FILE="/run/sync_status"
TMP_FILE=""
REQ_FILE=""

# shellcheck disable=SC2329 # invoked via trap
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

base64_encode_string() {
	printf '%s' "$1" | base64 | tr -d '\n'
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

read_config() {
	tz_name=""
	tz_data=""
	ntp_server_0=""
	ntp_server_1=""
	ntp_server_2=""
	ntp_server_3=""
	dhcp_ignore_timezone=""
	sync_status_raw_base64=""

	[ -f /etc/timezone ] && tz_name="$(cat /etc/timezone)"
	[ -f /etc/TZ ] && tz_data="$(cat /etc/TZ)"

	if [ "user" = "$(cat /etc/timezone.source 2>/dev/null)" ]; then
		dhcp_ignore_timezone="true"
	else
		dhcp_ignore_timezone="false"
	fi

	if [ -f "$NTP_WORKING_FILE" ]; then
		ntp_server_0="$(sed -n 1p "$NTP_WORKING_FILE" | cut -d' ' -f2)"
		ntp_server_1="$(sed -n 2p "$NTP_WORKING_FILE" | cut -d' ' -f2)"
		ntp_server_2="$(sed -n 3p "$NTP_WORKING_FILE" | cut -d' ' -f2)"
		ntp_server_3="$(sed -n 4p "$NTP_WORKING_FILE" | cut -d' ' -f2)"
	fi

	if [ -f "$SYNC_STATUS_FILE" ]; then
		sync_status_raw_base64="$(base64_encode_string "$(cat "$SYNC_STATUS_FILE")")"
	fi
}

write_config() {
	if [ -n "$tz_name" ]; then
		timectl set-timezone --source user "$tz_name"
	fi

	if [ "$dhcp_ignore_timezone" = "true" ]; then
		timectl pin-timezone
	elif [ "$dhcp_ignore_timezone" = "false" ]; then
		timectl unpin-timezone
	fi

	if [ -n "$ntp_server_0" ] || [ -n "$ntp_server_1" ] ||
		[ -n "$ntp_server_2" ] || [ -n "$ntp_server_3" ]; then
		servers="$ntp_server_0 $ntp_server_1 $ntp_server_2 $ntp_server_3"
		timectl set-ntp --source user "$servers"
	fi
}

read_body() {
	REQ_FILE=$(mktemp /tmp/time-req.XXXXXX)
	if [ -n "$CONTENT_LENGTH" ]; then
		dd bs=1 count="$CONTENT_LENGTH" 2>/dev/null >"$REQ_FILE"
	else
		cat >"$REQ_FILE"
	fi
}

handle_get() {
	read_config

	cat <<EOF
{
  "tz_name": "$(json_escape "$tz_name")",
  "tz_data": "$(json_escape "$tz_data")",
  "ntp_server_0": "$(json_escape "$ntp_server_0")",
  "ntp_server_1": "$(json_escape "$ntp_server_1")",
  "ntp_server_2": "$(json_escape "$ntp_server_2")",
  "ntp_server_3": "$(json_escape "$ntp_server_3")",
  "dhcp_ignore_timezone": "$(json_escape "$dhcp_ignore_timezone")",
  "sync_status_raw_base64": "$(json_escape "$sync_status_raw_base64")"
}
EOF
}

handle_post() {
	read_body

	action=$(jct "$REQ_FILE" get action 2>/dev/null)

	case "$action" in
		reset)
			if [ -f "/rom$NTP_DEFAULT_FILE" ]; then
				cp -f "/rom$NTP_DEFAULT_FILE" "$NTP_WORKING_FILE"
				send_json '{"status":"ok","message":"NTP configuration reset to defaults"}'
			else
				json_error 404 "Default NTP configuration not found" "404 Not Found"
			fi
			;;

		set_time)
			manual_time=$(jct "$REQ_FILE" get time 2>/dev/null)
			if [ -z "$manual_time" ]; then
				json_error 422 "Missing time parameter" "422 Unprocessable Entity"
			fi
			if timectl set-time "$manual_time"; then
				send_json "{\"status\":\"ok\",\"message\":\"Time set to $(date)\"}"
			else
				json_error 500 "Failed to set time" "500 Internal Server Error"
			fi
			;;

		update)
			tz_name=$(jct "$REQ_FILE" get tz_name 2>/dev/null)
			ntp_server_0=$(jct "$REQ_FILE" get ntp_server_0 2>/dev/null)
			ntp_server_1=$(jct "$REQ_FILE" get ntp_server_1 2>/dev/null)
			ntp_server_2=$(jct "$REQ_FILE" get ntp_server_2 2>/dev/null)
			ntp_server_3=$(jct "$REQ_FILE" get ntp_server_3 2>/dev/null)
			dhcp_ignore_timezone=$(jct "$REQ_FILE" get dhcp_ignore_timezone 2>/dev/null)

			if [ -z "$tz_name" ]; then
				json_error 422 "Timezone name cannot be empty" "422 Unprocessable Entity"
			fi

			write_config
			send_json '{"status":"ok","message":"Time configuration updated"}'
			;;

		*)
			json_error 400 "Unknown action: $action" "400 Bad Request"
			;;
	esac
}

case "$REQUEST_METHOD" in
	GET | "")
		send_json "$(handle_get)"
		;;
	POST)
		handle_post
		;;
	*)
		json_error 405 "Method not allowed" "405 Method Not Allowed"
		;;
esac
