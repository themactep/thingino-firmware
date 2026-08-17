#!/bin/sh
# shellcheck disable=SC1091,SC2034,SC2086,SC2329,SC3043

# Check authentication
. /var/www/x/auth.sh
require_auth

CRONTABS="/etc/cron/crontabs/root"

RECORD_FILENAME_FB="%Y%m%d/%H/%Y%m%dT%H%M%S"

vr_domain="recorder"
vr_config_file="/etc/prudynt.json"
vr_temp_config_file="/tmp/${vr_domain}.json"

request_body=""
MOUNTS_LIST=""

vr_defaults() {
	[ -z "$vr_autostart" ] && vr_autostart="false"
	[ -z "$vr_channel" ] && vr_channel=0
	[ -z "$vr_device_path" ] && vr_device_path="$(hostname)/records"
	[ -z "$vr_filename" ] && vr_filename="$RECORD_FILENAME_FB"
	case "$vr_filename" in
		*/) vr_filename="$RECORD_FILENAME_FB" ;;
	esac
	[ -z "$vr_duration" ] && vr_duration=60
	[ -z "$vr_limit" ] && vr_limit=15
	[ -z "$vr_min_free_mb" ] && vr_min_free_mb=500
	[ -z "$vr_check_interval" ] && vr_check_interval=60
	[ -z "$vr_cleanup_enabled" ] && vr_cleanup_enabled="false"
}

vr_set_value() {
	[ -f "$vr_temp_config_file" ] || echo '{}' >"$vr_temp_config_file"
	jct "$vr_temp_config_file" set "$vr_domain.$1" "$2" >/dev/null 2>&1
}

vr_get_value() {
	jct "$vr_config_file" get "$vr_domain.$1" 2>/dev/null
}

vr_read_config() {
	[ -f "$vr_config_file" ] || return
	vr_autostart=$(vr_get_value autostart)
	vr_channel=$(vr_get_value channel)
	vr_device_path=$(vr_get_value device_path)
	vr_duration=$(vr_get_value duration)
	vr_filename=$(vr_get_value filename)
	vr_limit=$(vr_get_value limit)
	vr_mount=$(vr_get_value mount)
	vr_min_free_mb=$(vr_get_value min_free_mb)
	vr_check_interval=$(vr_get_value check_interval)
	vr_cleanup_enabled=$(vr_get_value cleanup_enabled)
}

list_mounts() {
	awk '/cif|fat|nfs|smb/{print $2}' /etc/mtab 2>/dev/null
}

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

bool_to_json() {
	[ "${1}" = "true" ] && printf 'true' || printf 'false'
}

normalize_bool() {
	case "${1}" in
		1 | true | TRUE | on | ON | yes | YES) printf 'true' ;;
		*) printf 'false' ;;
	esac
}

is_positive_int() {
	case "$1" in
		'' | *[!0-9]*) return 1 ;;
	esac
	[ "$1" -gt 0 ] 2>/dev/null
}

is_non_negative_int() {
	case "$1" in
		'' | *[!0-9]*) return 1 ;;
	esac
	[ "$1" -ge 0 ] 2>/dev/null
}

urldecode() {
	printf '%b' "$(echo "$1" | sed 's/+/ /g; s/%\([0-9A-Fa-f][0-9A-Fa-f]\)/\\x\1/g')"
}

read_request_body() {
	request_body=""
	[ "$REQUEST_METHOD" = "POST" ] || return
	local length="${CONTENT_LENGTH:-0}"
	case "$length" in
		'' | *[!0-9]*) length=0 ;;
	esac
	if [ "$length" -gt 0 ] 2>/dev/null; then
		request_body=$(dd bs=1 count="$length" 2>/dev/null)
	else
		request_body=""
	fi
}

parse_form_data() {
	local data="$1" pair key value
	POST_form=""
	POST_tab=""
	[ -z "$data" ] && return
	local oldifs="$IFS"
	IFS='&'
	for pair in $data; do
		IFS="$oldifs"
		case "$pair" in
			*=*)
				key="${pair%%=*}"
				value="${pair#*=}"
				;;
			*)
				key="$pair"
				value=""
				;;
		esac
		key=$(urldecode "$key")
		value=$(urldecode "$value")
		case "$key" in
			form) POST_form="$value" ;;
			tab) POST_tab="$value" ;;
			vr_autostart) POST_vr_autostart="$value" ;;
			vr_channel) POST_vr_channel="$value" ;;
			vr_device_path) POST_vr_device_path="$value" ;;
			vr_duration) POST_vr_duration="$value" ;;
			vr_filename) POST_vr_filename="$value" ;;
			vr_limit) POST_vr_limit="$value" ;;
			vr_min_free_mb) POST_vr_min_free_mb="$value" ;;
			vr_check_interval) POST_vr_check_interval="$value" ;;
			vr_cleanup_enabled) POST_vr_cleanup_enabled="$value" ;;
			vr_mount) POST_vr_mount="$value" ;;
			*) : ;;
		esac
		IFS='&'
	done
	IFS="$oldifs"
}

refresh_settings() {
	vr_read_config
	vr_defaults
}

mounts_json() {
	local saved_ifs="$IFS"
	IFS='
'
	set -- $MOUNTS_LIST
	IFS="$saved_ifs"
	local first=1
	printf '['
	for mount in "$@"; do
		[ -z "$mount" ] && continue
		if [ $first -eq 0 ]; then printf ','; fi
		printf '"%s"' "$(json_escape "$mount")"
		first=0
	done
	printf ']'
}

collect_command_output() {
	local label="$1"
	shift
	{
		printf '$ %s\n' "$label"
		"$@"
	} 2>&1 || true
}

build_state_payload() {
	MOUNTS_LIST="$(list_mounts)"
	local mounts_json_str debug_video debug_crontab
	mounts_json_str=$(mounts_json)
	#debug_video="$(jct $vr_config_file get $vr_domain)"
	#debug_crontab="$(collect_command_output "crontab -l" crontab -l)"

	local video_channel video_duration video_limit video_min_free_mb video_check_interval
	video_channel="$vr_channel"
	case "$video_channel" in '' | *[!0-9]*) video_channel=0 ;; esac
	video_duration="$vr_duration"
	case "$video_duration" in '' | *[!0-9]*) video_duration=0 ;; esac
	video_limit="$vr_limit"
	case "$video_limit" in '' | *[!0-9]*) video_limit=0 ;; esac
	video_min_free_mb="$vr_min_free_mb"
	case "$video_min_free_mb" in '' | *[!0-9]*) video_min_free_mb=500 ;; esac
	video_check_interval="$vr_check_interval"
	case "$video_check_interval" in '' | *[!0-9]*) video_check_interval=60 ;; esac

	cat <<EOF
{
  "video": {
    "autostart": $(bool_to_json "$vr_autostart"),
    "channel": $video_channel,
    "check_interval": $video_check_interval,
    "cleanup_enabled": $(bool_to_json "$vr_cleanup_enabled"),
    "device_path": "$(json_escape "$vr_device_path")",
    "duration": $video_duration,
    "filename": "$(json_escape "$vr_filename")",
    "limit": $video_limit,
    "min_free_mb": $video_min_free_mb,
    "mount": "$(json_escape "$vr_mount")"

  "mounts": $mounts_json_str,
  "messages": {
    "strftime_hint": "$(json_escape "$STR_SUPPORTS_STRFTIME")"
  },
  "debug": {
    "video": "$debug_video",
    "crontab": "$debug_crontab"
  }
}
EOF
}

send_state_response() {
	local message="$1"
	refresh_settings
	local data
	data=$(build_state_payload)
	if [ -n "$message" ]; then
		send_json "{\"ok\":true,\"message\":\"$(json_escape "$message")\",\"data\":$data}"
	else
		send_json "{\"ok\":true,\"data\":$data}"
	fi
}

process_video_form() {
	refresh_settings
	vr_autostart="$POST_vr_autostart"
	vr_channel="$POST_vr_channel"
	vr_cleanup_enabled="$POST_vr_cleanup_enabled"
	vr_device_path="$POST_vr_device_path"
	vr_duration="$POST_vr_duration"
	vr_filename="$POST_vr_filename"
	vr_limit="$POST_vr_limit"
	vr_min_free_mb="$POST_vr_min_free_mb"
	vr_check_interval="$POST_vr_check_interval"
	vr_mount="$POST_vr_mount"
	vr_defaults

	vr_autostart=$(normalize_bool "$vr_autostart")
	vr_cleanup_enabled=$(normalize_bool "$vr_cleanup_enabled")
	case "$vr_channel" in 0 | 1) : ;; *) vr_channel=0 ;; esac
	if ! is_positive_int "$vr_duration"; then
		json_error 422 "Clip duration must be a positive integer"
	fi
	if ! is_positive_int "$vr_limit"; then
		json_error 422 "Storage limit must be a positive integer"
	fi
	if ! is_positive_int "$vr_min_free_mb"; then
		json_error 422 "Minimum free space must be a positive integer"
	fi
	if ! is_positive_int "$vr_check_interval"; then
		json_error 422 "Check interval must be a positive integer"
	fi
	[ -z "$vr_mount" ] && json_error 422 "Record mount cannot be empty."
	case "$vr_filename" in
		/*) vr_filename="${vr_filename#/}" ;;
	esac
	[ -z "$vr_filename" ] && json_error 422 "Record filename cannot be empty."

	vr_set_value autostart "$vr_autostart"
	vr_set_value channel "$vr_channel"
	vr_set_value check_interval "$vr_check_interval"
	vr_set_value cleanup_enabled "$vr_cleanup_enabled"
	vr_set_value device_path "$vr_device_path"
	vr_set_value duration "$vr_duration"
	vr_set_value filename "$vr_filename"
	vr_set_value limit "$vr_limit"
	vr_set_value min_free_mb "$vr_min_free_mb"
	vr_set_value mount "$vr_mount"

	if ! jct "$vr_config_file" import "$vr_temp_config_file"; then
		rm -f "$vr_temp_config_file"
		json_error 500 "Failed to update video recorder configuration"
	fi
	rm -f "$vr_temp_config_file"
	update_caminfo
	/etc/init.d/S95recordmgr restart >/dev/null 2>&1 || true
	send_state_response "Video recorder settings updated."
}

REQUEST_METHOD=${REQUEST_METHOD:-GET}

case "$REQUEST_METHOD" in
	GET | HEAD)
		send_state_response ""
		;;
	POST)
		read_request_body
		parse_form_data "$request_body"
		case "$POST_form" in
			video) process_video_form ;;
			*) json_error 400 "Unsupported form submission" ;;
		esac
		;;
	*)
		json_error 405 "Method not allowed" "405 Method Not Allowed"
		;;
esac
