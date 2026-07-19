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

thingino_heartbeat_native_payload() {
	# Quick path: read daynight mode and brightness from daynightd's files.
	# For full sensor data (total_gain, EV, etc), read /run/thingino/daynight_sensors.
	# Also try prudyntctl for mic/spk/image data which only prudynt can provide.

	now=$(date +%s)
	uptime=$(cut -d '.' -f 1 /proc/uptime 2>/dev/null || printf '0')

	# daynightd is the single source of truth for photosensing
	daynight_mode="unknown"
	if [ -r /run/thingino/daynight_mode ]; then
		daynight_mode=$(cat /run/thingino/daynight_mode 2>/dev/null | tr -d '\n')
	fi

	daynight_brightness="null"
	if [ -r /run/thingino/daynight_brightness ]; then
		_v=$(cat /run/thingino/daynight_brightness 2>/dev/null | tr -d '\n')
		[ -n "$_v" ] && daynight_brightness=$_v
	fi

	# Sensor telemetry from daynightd's JSON file.
	# Use brightness_percent for the button display (0-100, user-friendly).
	# ev_log2 / primary_signal are available in the sensor file for charts.
	total_gain="null"
	if [ -r /run/thingino/daynight_sensors ] && command -v jct >/dev/null 2>&1; then
		_bp=$(jct /run/thingino/daynight_sensors get brightness_percent 2>/dev/null | tr -d '\n"')
		[ -n "$_bp" ] && [ "$_bp" != "null" ] && total_gain=$_bp
	fi

	_color_mode="null"
	case "$daynight_mode" in
		day) _color_mode=0 ;;
		night) _color_mode=1 ;;
	esac

	# Audio and image from prudyntctl (prudynt still owns these)
	mic_enabled=0
	spk_enabled=0
	unset _mic_queried _spk_queried
	if command -v prudyntctl >/dev/null 2>&1; then
		_tmp=$(mktemp)
		if timeout 1 prudyntctl json '{"audio":{"mic_enabled":null,"spk_enabled":null},"image":{"running_mode":null}}' >"$_tmp" 2>/dev/null; then
			_mic_val=$(jct "$_tmp" get audio.mic_enabled 2>/dev/null | tr -d '\n"')
			case "$_mic_val" in true | 1)
				mic_enabled=1
				_mic_queried=1
				;;
			*)
				mic_enabled=0
				_mic_queried=1
				;;
			esac
			_spk_val=$(jct "$_tmp" get audio.spk_enabled 2>/dev/null | tr -d '\n"')
			case "$_spk_val" in true | 1)
				spk_enabled=1
				_spk_queried=1
				;;
			*)
				spk_enabled=0
				_spk_queried=1
				;;
			esac
			# Use image.running_mode from prudynt as color_mode if daynight_mode unknown
			if [ "$daynight_mode" = "unknown" ]; then
				_cm=$(jct "$_tmp" get image.running_mode 2>/dev/null | tr -d '\n"')
				case "$_cm" in 1) _color_mode=1 ;; 0) _color_mode=0 ;; esac
			fi
		fi
		rm -f "$_tmp"
	fi

	daynight_enabled="false"
	if [ -f /etc/thingino.json ] && command -v jct >/dev/null 2>&1; then
		_val=$(jct /etc/thingino.json get daynight.enabled 2>/dev/null | tr -d '\n"')
		case "$_val" in true | 1) daynight_enabled=1 ;; *) daynight_enabled=0 ;; esac
	elif [ -f /etc/prudynt.json ] && command -v jct >/dev/null 2>&1; then
		_val=$(jct /etc/prudynt.json get daynight.enabled 2>/dev/null | tr -d '\n"')
		case "$_val" in true | 1) daynight_enabled=1 ;; *) daynight_enabled=0 ;; esac
	fi

	rec_ch0=0
	rec_ch1=0
	[ -f /run/prudynt/mp4ctl-ch0.active ] && rec_ch0=1
	[ -f /run/prudynt/mp4ctl-ch1.active ] && rec_ch1=1

	motion_enabled=0
	[ -f /run/prudynt/motion.active ] && motion_enabled=1

	privacy_enabled=0
	[ -f /run/prudynt/privacy.active ] && privacy_enabled=1

	# mic/spk: prefer prudyntctl query, fall back to runtime files
	if [ -z "${_mic_queried:-}" ]; then
		mic_enabled=0
		[ -f /run/prudynt/mic.active ] && mic_enabled=1
		spk_enabled=0
		[ -f /run/prudynt/spk.active ] && spk_enabled=1
	fi

	wg_status="0"
	if command -v wg >/dev/null 2>&1; then
		case "$(wg show wg0 2>/dev/null)" in
			*"latest handshake"*) wg_status="1" ;;
		esac
	fi

	printf '{"time_now":%s,"uptime":%s,"daynight_brightness":%s,"total_gain":%s,"daynight_mode":"%s","rec_ch0":%s,"rec_ch1":%s,"motion_enabled":%s,"privacy_enabled":%s,"color_mode":%s,"mic_enabled":%s,"spk_enabled":%s,"daynight_enabled":%s,"ircut_state":null,"ir850_state":null,"ir940_state":null,"white_state":null,"wg_status":%s}\n' \
		"$now" "$uptime" "$daynight_brightness" "$total_gain" "$daynight_mode" "$rec_ch0" "$rec_ch1" \
		"$motion_enabled" "$privacy_enabled" "$_color_mode" "$mic_enabled" "$spk_enabled" \
		"$daynight_enabled" "$wg_status"
}

thingino_heartbeat_payload() {
	thingino_heartbeat_native_payload
}
