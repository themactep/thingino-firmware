#!/bin/sh

THINGINO_CONFIG="${THINGINO_CONFIG:-/etc/thingino.json}"
THINGINO_RAPTOR_CONFIG="${THINGINO_RAPTOR_CONFIG:-/etc/raptor.conf}"
THINGINO_IRCUT_MODE_FILE="${THINGINO_IRCUT_MODE_FILE:-/tmp/ircutmode.txt}"

thingino_heartbeat_agent_port() {
	port=
	if command -v jct >/dev/null 2>&1 && [ -f "$THINGINO_CONFIG" ]; then
		port=$(jct "$THINGINO_CONFIG" get agent.port 2>/dev/null | tr -d '\r\n"')
	fi
	case "$port" in
		'' | *[!0-9]*) port=1998 ;;
		0) port=1998 ;;
	esac
	printf '%s' "$port"
}

thingino_heartbeat_agent_url() {
	printf 'http://127.0.0.1:%s' "$(thingino_heartbeat_agent_port)"
}

thingino_heartbeat_agent_request() {
	path=$1
	curl -sS --max-time 2 "$(thingino_heartbeat_agent_url)$path" 2>/dev/null
}

thingino_heartbeat_agent_backend_name() {
	device_json=$(thingino_heartbeat_agent_request /api/v1/device)
	[ -n "$device_json" ] || return 1
	printf '%s\n' "$device_json" |
		sed -n 's/.*"backend"[[:space:]]*:[[:space:]]*{[^}]*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' |
		head -n 1
}

thingino_heartbeat_json_string_field() {
	key=$1
	json=$2
	printf '%s\n' "$json" |
		sed -n 's/.*"'"$key"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' |
		head -n 1
}

thingino_heartbeat_json_number_field() {
	key=$1
	json=$2
	printf '%s\n' "$json" |
		sed -n 's/.*"'"$key"'"[[:space:]]*:[[:space:]]*\(-\{0,1\}[0-9][0-9]*\(\.[0-9][0-9]*\)\{0,1\}\).*/\1/p' |
		head -n 1
}

thingino_heartbeat_json_bool_field() {
	key=$1
	json=$2
	value=$(printf '%s\n' "$json" |
		sed -n 's/.*"'"$key"'"[[:space:]]*:[[:space:]]*\(true\|false\).*/\1/p' |
		head -n 1)
	case "$value" in
		true | false)
			printf '%s' "$value"
			;;
		*)
			return 1
			;;
	esac
}

thingino_heartbeat_config_get() {
	section=$1
	key=$2
	default_value=$3
	if ! command -v raptorctl >/dev/null 2>&1; then
		printf '%s' "$default_value"
		return 0
	fi
	value=$(raptorctl config get "$section" "$key" 2>/dev/null | tr -d '\r\n"')
	if [ -n "$value" ]; then
		printf '%s' "$value"
	else
		printf '%s' "$default_value"
	fi
}

thingino_heartbeat_bool_json() {
	case "$(printf '%s' "$1" | tr 'A-Z' 'a-z')" in
		1 | true | yes | on)
			printf 'true'
			;;
		0 | false | no | off)
			printf 'false'
			;;
		*)
			printf '%s' "${2:-false}"
			;;
	esac
}

thingino_heartbeat_config_bool_json() {
	printf '%s' "$(thingino_heartbeat_bool_json "$(thingino_heartbeat_config_get "$1" "$2" "$3")")"
}

thingino_heartbeat_command_bool() {
	command_name=$1
	default_value=$2
	if ! command -v "$command_name" >/dev/null 2>&1; then
		printf '%s' "$default_value"
		return 0
	fi
	value=$("$command_name" status 2>/dev/null | tr -d '\r\n')
	case "$value" in
		true | false)
			printf '%s' "$value"
			;;
		*)
			printf '%s' "$default_value"
			;;
	esac
}

thingino_heartbeat_light_state() {
	light_type=$1
	if ! command -v light >/dev/null 2>&1; then
		printf 'null'
		return 0
	fi
	value=$(light "$light_type" read 2>/dev/null | tr -d '\r\n')
	case "$value" in
		0 | 1)
			printf '%s' "$value"
			;;
		*)
			printf 'null'
			;;
	esac
}

thingino_heartbeat_ircut_state() {
	if [ -r "$THINGINO_IRCUT_MODE_FILE" ]; then
		value=$(sed -n '1p' "$THINGINO_IRCUT_MODE_FILE" 2>/dev/null | tr -d '\r\n ')
	fi
	case "$value" in
		0 | 1)
			printf '%s' "$value"
			;;
		*)
			printf 'null'
			;;
	esac
}

thingino_heartbeat_daynight_mode() {
	ric_status=$1
	mode=$(thingino_heartbeat_json_string_field state "$ric_status")
	case "$mode" in
		day | night)
			printf '%s' "$mode"
			return 0
			;;
	esac

	case "$(thingino_heartbeat_ircut_state)" in
		0)
			printf 'night'
			;;
		1)
			printf 'day'
			;;
		*)
			printf 'unknown'
			;;
	esac
}

thingino_heartbeat_daynight_auto_enabled() {
	ric_status=$1
	mode=$(thingino_heartbeat_json_string_field mode "$ric_status")
	[ -n "$mode" ] || mode=$(thingino_heartbeat_config_get ircut mode auto)
	printf '%s' "$(thingino_heartbeat_bool_json "$([ "$mode" = auto ] && printf true || printf false)")"
}

thingino_heartbeat_record_channel() {
	value=$(thingino_heartbeat_config_get recording stream 0)
	case "$value" in
		'' | *[!0-9]*)
			printf '0'
			;;
		*)
			printf '%s' "$value"
			;;
	esac
}

thingino_heartbeat_wireguard_status() {
	if ip link show wg0 2>/dev/null | grep -q 'state UP'; then
		printf '1'
	else
		printf '0'
	fi
}

thingino_heartbeat_raptor_available() {
	[ -f "$THINGINO_RAPTOR_CONFIG" ] && command -v raptorctl >/dev/null 2>&1
}

thingino_heartbeat_raptor_payload() {
	now=$(date +%s)
	uptime=$(cut -d '.' -f 1 /proc/uptime 2>/dev/null || printf '0')
	ric_status=$(raptorctl ric status 2>/dev/null || true)
	rmr_status=$(raptorctl rmr status 2>/dev/null || true)

	daynight_mode=$(thingino_heartbeat_daynight_mode "$ric_status")
	daynight_enabled=$(thingino_heartbeat_daynight_auto_enabled "$ric_status")
	daynight_brightness=$(thingino_heartbeat_json_number_field ae_luma "$ric_status")
	total_gain=$(thingino_heartbeat_json_number_field total_gain "$ric_status")
	[ -n "$daynight_brightness" ] || daynight_brightness=null
	[ -n "$total_gain" ] || total_gain=null

	case "$daynight_mode" in
		day)
			color_mode=0
			;;
		night)
			color_mode=1
			;;
		*)
			color_mode=null
			;;
	esac

	rec_ch0=false
	rec_ch1=false
	recording=$(thingino_heartbeat_json_bool_field recording "$rmr_status" || printf 'false')
	case "$(thingino_heartbeat_record_channel)" in
		0)
			rec_ch0=$recording
			;;
		1)
			rec_ch1=$recording
			;;
	esac

	printf '{"time_now":%s,"uptime":%s,"daynight_brightness":%s,"total_gain":%s,"daynight_mode":"%s","rec_ch0":%s,"rec_ch1":%s,"motion_enabled":%s,"privacy_enabled":false,"color_mode":%s,"mic_enabled":%s,"spk_enabled":%s,"daynight_enabled":%s,"ircut_state":%s,"ir850_state":%s,"ir940_state":%s,"white_state":%s,"wg_status":%s}\n' \
		"$now" \
		"$uptime" \
		"$daynight_brightness" \
		"$total_gain" \
		"$daynight_mode" \
		"$rec_ch0" \
		"$rec_ch1" \
		"$(thingino_heartbeat_config_bool_json motion enabled false)" \
		"$color_mode" \
		"$(thingino_heartbeat_command_bool microphone "$(thingino_heartbeat_config_bool_json audio enabled true)")" \
		"$(thingino_heartbeat_command_bool speaker "$(thingino_heartbeat_config_bool_json audio ao_enabled false)")" \
		"$daynight_enabled" \
		"$(thingino_heartbeat_ircut_state)" \
		"$(thingino_heartbeat_light_state ir850)" \
		"$(thingino_heartbeat_light_state ir940)" \
		"$(thingino_heartbeat_light_state white)" \
		"$(thingino_heartbeat_wireguard_status)"
}

thingino_heartbeat_payload() {
	agent_heartbeat=$(thingino_heartbeat_agent_request /api/v1/runtime/heartbeat)
	agent_backend=$(thingino_heartbeat_agent_backend_name || true)

	if [ "$agent_backend" = "none" ] && thingino_heartbeat_raptor_available; then
		thingino_heartbeat_raptor_payload
		return 0
	fi

	if [ -n "$agent_heartbeat" ]; then
		printf '%s\n' "$agent_heartbeat"
		return 0
	fi

	if thingino_heartbeat_raptor_available; then
		thingino_heartbeat_raptor_payload
		return 0
	fi

	printf '{}\n'
}
