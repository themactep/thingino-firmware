#!/bin/sh
# shellcheck disable=SC1091,SC3043
# Timelapse configuration for raptor images.
# rmr owns timelapse natively (config section [timelapse] in raptor.conf);
# this CGI only reads/writes those keys through raptorctl. There is no cron
# schedule - rmr captures and rotates the files itself.

. /var/www/x/auth.sh
require_auth

CONFIG_SECTION="timelapse"

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

json_escape() {
	printf '%s' "$1" | sed \
		-e 's/\\/\\\\/g' \
		-e 's/"/\\"/g' \
		-e "s/\r/\\r/g" \
		-e "s/\n/\\n/g"
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

is_int_in_range() {
	value=$1
	min=$2
	max=$3
	case "$value" in
		'' | *[!0-9]*) return 1 ;;
	esac
	[ "$value" -ge "$min" ] 2>/dev/null && [ "$value" -le "$max" ] 2>/dev/null
}

config_get() {
	key=$1
	raptorctl config get "$CONFIG_SECTION" "$key" 2>/dev/null | tr -d '\r\n"'
}

config_set() {
	key=$1
	value=$2
	raptorctl config set "$CONFIG_SECTION" "$key" "$value" >/dev/null 2>&1
}

read_config() {
	tl_enabled=$(config_get enabled)
	tl_interval=$(config_get interval)
	tl_playback_fps=$(config_get playback_fps)
	tl_file_frames=$(config_get file_frames)
	tl_max_mb=$(config_get max_mb)
}

defaults() {
	case "$tl_enabled" in true | false) : ;; *) tl_enabled=false ;; esac
	case "$tl_interval" in '' | *[!0-9]*) tl_interval=10 ;; esac
	case "$tl_playback_fps" in '' | *[!0-9]*) tl_playback_fps=30 ;; esac
	case "$tl_file_frames" in '' | *[!0-9]*) tl_file_frames=0 ;; esac
	case "$tl_max_mb" in '' | *[!0-9]*) tl_max_mb=2048 ;; esac
}

storage_path() {
	path=$(raptorctl config get recording storage_path 2>/dev/null | tr -d '\r\n"')
	[ -n "$path" ] || path=/mnt/mmcblk0p1/raptor
	printf '%s/timelapse' "${path%/}"
}

build_state_payload() {
	cat <<EOF
{
  "timelapse": {
    "enabled": $(bool_to_json "$tl_enabled"),
    "interval": $tl_interval,
    "playback_fps": $tl_playback_fps,
    "file_frames": $tl_file_frames,
    "max_mb": $tl_max_mb
  },
  "storage_path": "$(json_escape "$(storage_path)")"
}
EOF
}

send_state_response() {
	local message="$1"
	read_config
	defaults
	local data
	data=$(build_state_payload)
	if [ -n "$message" ]; then
		send_json "{\"ok\":true,\"message\":\"$(json_escape "$message")\",\"data\":$data}"
	else
		send_json "{\"ok\":true,\"data\":$data}"
	fi
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
			enabled) POST_enabled="$value" ;;
			interval) POST_interval="$value" ;;
			playback_fps) POST_playback_fps="$value" ;;
			file_frames) POST_file_frames="$value" ;;
			max_mb) POST_max_mb="$value" ;;
			*) : ;;
		esac
		IFS='&'
	done
	IFS="$oldifs"
}

process_form() {
	read_config
	tl_enabled="$POST_enabled"
	tl_interval="$POST_interval"
	tl_playback_fps="$POST_playback_fps"
	tl_file_frames="$POST_file_frames"
	tl_max_mb="$POST_max_mb"
	defaults

	tl_enabled=$(normalize_bool "$tl_enabled")
	if ! is_int_in_range "$tl_interval" 2 86400; then
		json_error 422 "Interval must be an integer between 2 and 86400 seconds"
	fi
	if ! is_int_in_range "$tl_playback_fps" 1 120; then
		json_error 422 "Playback FPS must be an integer between 1 and 120"
	fi
	case "$tl_file_frames" in
		0) : ;;
		*)
			if ! is_int_in_range "$tl_file_frames" 60 1000000000; then
				json_error 422 "File rotation must be 0 (one file per day) or at least 60 frames"
			fi
			;;
	esac
	if ! is_int_in_range "$tl_max_mb" 0 1000000000; then
		json_error 422 "Storage quota must be zero or greater"
	fi

	config_set enabled "$tl_enabled"
	config_set interval "$tl_interval"
	config_set playback_fps "$tl_playback_fps"
	config_set file_frames "$tl_file_frames"
	config_set max_mb "$tl_max_mb"
	raptorctl config save >/dev/null 2>&1 || true

	send_state_response "Timelapse recorder settings updated."
}

REQUEST_METHOD=${REQUEST_METHOD:-GET}

case "$REQUEST_METHOD" in
	GET | HEAD)
		send_state_response ""
		;;
	POST)
		read_request_body
		parse_form_data "$request_body"
		process_form
		;;
	*)
		json_error 405 "Method not allowed" "405 Method Not Allowed"
		;;
esac
