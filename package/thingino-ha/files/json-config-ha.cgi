#!/bin/sh

# Check authentication
. /var/www/x/auth.sh
require_auth

DOMAIN="ha"
CONFIG_FILE="/etc/thingino.json"
TMP_FILE=""
REQ_FILE=""
MERGED_FILE=""
RESTART_FLAG="/tmp/ha-restart.pending"
RESTART_PID_FILE="/tmp/ha-restart.worker.pid"
REFRESH_FLAG="/tmp/ha-refresh.pending"
REFRESH_PID_FILE="/tmp/ha-refresh.worker.pid"

cleanup() {
	[ -n "$TMP_FILE" ] && rm -f "$TMP_FILE"
	[ -n "$REQ_FILE" ] && rm -f "$REQ_FILE"
	[ -n "$MERGED_FILE" ] && rm -f "$MERGED_FILE"
}
trap cleanup EXIT

json_escape() {
	printf '%s' "$1" | sed \
		-e 's/\\/\\\\/g' \
		-e 's/"/\\"/g' \
		-e "s/\r/\\r/g" \
		-e "s/\n/\\n/g"
}

json_string() {
	printf '"%s"' "$(json_escape "$1")"
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

normalize_uint_in_range() {
	value="$1"
	default_value="$2"
	min_value="$3"
	max_value="$4"
	field_name="$5"

	[ -n "$value" ] || {
		printf '%s' "$default_value"
		return 0
	}

	case "$value" in
		*[!0-9]* | '') json_error 422 "${field_name} must be a positive integer" "422 Unprocessable Entity" ;;
	esac

	if [ "$value" -lt "$min_value" ] || [ "$value" -gt "$max_value" ]; then
		json_error 422 "${field_name} must be between ${min_value} and ${max_value}" "422 Unprocessable Entity"
	fi

	printf '%s' "$value"
}

stored_string_default() {
	key="$1"
	default_value="$2"
	value=$(strip_json_string "$(jct "$CONFIG_FILE" get "$key" 2>/dev/null)")
	[ -n "$value" ] || value="$default_value"
	printf '%s' "$value"
}

stored_bool_default() {
	key="$1"
	default_value="$2"
	raw=$(jct "$CONFIG_FILE" get "$key" 2>/dev/null)

	case "$(printf '%s' "$raw" | tr 'A-Z' 'a-z' | tr -d '"')" in
		1 | true | yes | on) printf 'true' ;;
		0 | false | no | off) printf 'false' ;;
		'' | null) printf '%s' "$default_value" ;;
		*) printf '%s' "$default_value" ;;
	esac
}

stored_uint_default() {
	key="$1"
	default_value="$2"
	value=$(strip_json_string "$(jct "$CONFIG_FILE" get "$key" 2>/dev/null)")
	case "$value" in
		'' | *[!0-9]*) printf '%s' "$default_value" ;;
		*) printf '%s' "$value" ;;
	esac
}

ensure_config() {
	if [ ! -f "$CONFIG_FILE" ]; then
		umask 077
		echo '{}' >"$CONFIG_FILE"
	fi
}

write_payload_file() {
	TMP_FILE=$(mktemp /tmp/${DOMAIN}.XXXXXX) ||
		json_error 500 "Failed to create temporary Home Assistant config" "500 Internal Server Error"

	cat >"$TMP_FILE" <<EOF
{
  "${DOMAIN}": {
    "enabled": ${enabled},
    "device_name": $(json_string "$device_name"),
    "device_model": $(json_string "$device_model"),
    "discovery_prefix": $(json_string "$discovery_prefix"),
    "state_interval": ${state_interval},
    "discovery_interval": ${discovery_interval},
    "mqtt": {
      "host": $(json_string "$mqtt_host"),
      "port": ${mqtt_port},
      "username": $(json_string "$mqtt_username"),
      "password": $(json_string "$mqtt_password"),
      "client_id_prefix": $(json_string "$mqtt_client_id"),
      "use_ssl": ${mqtt_ssl}
    },
    "enable_motion": ${en_motion},
    "enable_motion_guard": ${en_motion_guard},
    "enable_ircut": ${en_ircut},
    "enable_daynight": ${en_daynight},
    "enable_privacy": ${en_privacy},
    "enable_color": ${en_color},
    "enable_ir850": ${en_ir850},
    "enable_ir940": ${en_ir940},
    "enable_white_light": ${en_white},
    "enable_gain": ${en_gain},
    "enable_rssi": ${en_rssi},
    "enable_snapshot": ${en_snapshot},
    "enable_reboot": ${en_reboot},
    "enable_ota": ${en_ota}
  }
}
EOF
}

effective_ha_config_json() {
	MERGED_FILE=$(mktemp /tmp/${DOMAIN}-merged.XXXXXX) ||
		json_error 500 "Failed to create merged Home Assistant config" "500 Internal Server Error"

	cp "$CONFIG_FILE" "$MERGED_FILE" ||
		json_error 500 "Failed to stage merged Home Assistant config" "500 Internal Server Error"

	jct "$MERGED_FILE" import "$TMP_FILE" >/dev/null 2>&1 ||
		json_error 500 "Failed to merge Home Assistant configuration" "500 Internal Server Error"

	jct "$MERGED_FILE" get "$DOMAIN" 2>/dev/null
}

schedule_ha_restart() {
	worker_pid=$(cat "$RESTART_PID_FILE" 2>/dev/null)
	: >"$RESTART_FLAG"

	if [ -n "$worker_pid" ] && kill -0 "$worker_pid" 2>/dev/null; then
		return 0
	fi

	rm -f "$RESTART_PID_FILE"

	if command -v setsid >/dev/null 2>&1; then
		setsid sh -c '
      flag="$1"
      pidfile="$2"

      printf "%s\n" "$$" > "$pidfile"
      trap "rm -f \"$pidfile\"" EXIT

      while [ -f "$flag" ]; do
        rm -f "$flag"
        /etc/init.d/S93ha restart >/dev/null 2>&1
      done
    ' sh "$RESTART_FLAG" "$RESTART_PID_FILE" >/dev/null 2>&1 &
	else
		(
			printf "%s\n" "$$" >"$RESTART_PID_FILE"
			trap 'rm -f "$RESTART_PID_FILE"' EXIT

			while [ -f "$RESTART_FLAG" ]; do
				rm -f "$RESTART_FLAG"
				/etc/init.d/S93ha restart >/dev/null 2>&1
			done
		) >/dev/null 2>&1 &
	fi
}

schedule_ha_refresh() {
	worker_pid=$(cat "$REFRESH_PID_FILE" 2>/dev/null)
	: >"$REFRESH_FLAG"

	if [ -n "$worker_pid" ] && kill -0 "$worker_pid" 2>/dev/null; then
		return 0
	fi

	rm -f "$REFRESH_PID_FILE"

	if command -v setsid >/dev/null 2>&1; then
		setsid sh -c '
      flag="$1"
      pidfile="$2"

      printf "%s\n" "$$" > "$pidfile"
      trap "rm -f \"$pidfile\"" EXIT

      while [ -f "$flag" ]; do
        rm -f "$flag"
        if pidof ha-daemon >/dev/null 2>&1; then
          /usr/sbin/ha-discovery >/dev/null 2>&1
          /usr/sbin/ha-state force >/dev/null 2>&1
        elif jct /etc/thingino.json get ha.enabled 2>/dev/null | grep -qi true; then
          /etc/init.d/S93ha start >/dev/null 2>&1
        fi
      done
    ' sh "$REFRESH_FLAG" "$REFRESH_PID_FILE" >/dev/null 2>&1 &
	else
		(
			printf "%s\n" "$$" >"$REFRESH_PID_FILE"
			trap 'rm -f "$REFRESH_PID_FILE"' EXIT

			while [ -f "$REFRESH_FLAG" ]; do
				rm -f "$REFRESH_FLAG"
				if pidof ha-daemon >/dev/null 2>&1; then
					/usr/sbin/ha-discovery >/dev/null 2>&1
					/usr/sbin/ha-state force >/dev/null 2>&1
				elif jct /etc/thingino.json get ha.enabled 2>/dev/null | grep -qi true; then
					/etc/init.d/S93ha start >/dev/null 2>&1
				fi
			done
		) >/dev/null 2>&1 &
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
	local data
	data=$(jct "$CONFIG_FILE" get "$DOMAIN" 2>/dev/null)
	case "$data" in
		"" | null) data='{}' ;;
	esac
	send_json "$data"
}

handle_post() {
	read_body
	ensure_config

	old_enabled=$(stored_bool_default "${DOMAIN}.enabled" "false")
	old_device_name=$(stored_string_default "${DOMAIN}.device_name" "")
	old_device_model=$(stored_string_default "${DOMAIN}.device_model" "")
	old_discovery_prefix=$(stored_string_default "${DOMAIN}.discovery_prefix" "homeassistant")
	old_state_interval=$(stored_uint_default "${DOMAIN}.state_interval" "15")
	old_discovery_interval=$(stored_uint_default "${DOMAIN}.discovery_interval" "3600")
	old_mqtt_host=$(stored_string_default "${DOMAIN}.mqtt.host" "")
	old_mqtt_port=$(stored_uint_default "${DOMAIN}.mqtt.port" "1883")
	old_mqtt_username=$(stored_string_default "${DOMAIN}.mqtt.username" "")
	old_mqtt_password=$(stored_string_default "${DOMAIN}.mqtt.password" "")
	old_mqtt_client_id=$(stored_string_default "${DOMAIN}.mqtt.client_id_prefix" "thingino-ha")
	old_mqtt_ssl=$(stored_bool_default "${DOMAIN}.mqtt.use_ssl" "false")
	old_en_motion=$(stored_bool_default "${DOMAIN}.enable_motion" "true")
	old_en_motion_guard=$(stored_bool_default "${DOMAIN}.enable_motion_guard" "true")
	old_en_ircut=$(stored_bool_default "${DOMAIN}.enable_ircut" "true")
	old_en_daynight=$(stored_bool_default "${DOMAIN}.enable_daynight" "true")
	old_en_privacy=$(stored_bool_default "${DOMAIN}.enable_privacy" "true")
	old_en_color=$(stored_bool_default "${DOMAIN}.enable_color" "true")
	old_en_ir850=$(stored_bool_default "${DOMAIN}.enable_ir850" "true")
	old_en_ir940=$(stored_bool_default "${DOMAIN}.enable_ir940" "true")
	old_en_white=$(stored_bool_default "${DOMAIN}.enable_white_light" "true")
	old_en_gain=$(stored_bool_default "${DOMAIN}.enable_gain" "true")
	old_en_rssi=$(stored_bool_default "${DOMAIN}.enable_rssi" "true")
	old_en_snapshot=$(stored_bool_default "${DOMAIN}.enable_snapshot" "true")
	old_en_reboot=$(stored_bool_default "${DOMAIN}.enable_reboot" "true")
	old_en_ota=$(stored_bool_default "${DOMAIN}.enable_ota" "true")

	# Top-level fields
	new_enabled=$(jct "$REQ_FILE" get enabled 2>/dev/null)
	new_device_name=$(jct "$REQ_FILE" get device_name 2>/dev/null)
	new_device_model=$(jct "$REQ_FILE" get device_model 2>/dev/null)
	new_discovery_prefix=$(jct "$REQ_FILE" get discovery_prefix 2>/dev/null)
	new_state_interval=$(jct "$REQ_FILE" get state_interval 2>/dev/null)
	new_discovery_interval=$(jct "$REQ_FILE" get discovery_interval 2>/dev/null)

	# MQTT nested fields
	new_mqtt_host=$(jct "$REQ_FILE" get mqtt.host 2>/dev/null)
	new_mqtt_port=$(jct "$REQ_FILE" get mqtt.port 2>/dev/null)
	new_mqtt_username=$(jct "$REQ_FILE" get mqtt.username 2>/dev/null)
	new_mqtt_password=$(jct "$REQ_FILE" get mqtt.password 2>/dev/null)
	new_mqtt_client_id=$(jct "$REQ_FILE" get mqtt.client_id_prefix 2>/dev/null)
	new_mqtt_ssl=$(jct "$REQ_FILE" get mqtt.use_ssl 2>/dev/null)

	# Entity toggles
	new_en_motion=$(jct "$REQ_FILE" get enable_motion 2>/dev/null)
	new_en_motion_guard=$(jct "$REQ_FILE" get enable_motion_guard 2>/dev/null)
	new_en_ircut=$(jct "$REQ_FILE" get enable_ircut 2>/dev/null)
	new_en_daynight=$(jct "$REQ_FILE" get enable_daynight 2>/dev/null)
	new_en_privacy=$(jct "$REQ_FILE" get enable_privacy 2>/dev/null)
	new_en_color=$(jct "$REQ_FILE" get enable_color 2>/dev/null)
	new_en_ir850=$(jct "$REQ_FILE" get enable_ir850 2>/dev/null)
	new_en_ir940=$(jct "$REQ_FILE" get enable_ir940 2>/dev/null)
	new_en_white=$(jct "$REQ_FILE" get enable_white_light 2>/dev/null)
	new_en_gain=$(jct "$REQ_FILE" get enable_gain 2>/dev/null)
	new_en_rssi=$(jct "$REQ_FILE" get enable_rssi 2>/dev/null)
	new_en_snapshot=$(jct "$REQ_FILE" get enable_snapshot 2>/dev/null)
	new_en_reboot=$(jct "$REQ_FILE" get enable_reboot 2>/dev/null)
	new_en_ota=$(jct "$REQ_FILE" get enable_ota 2>/dev/null)

	# Normalize
	enabled=$(normalize_bool "$new_enabled")
	mqtt_ssl=$(normalize_bool "$new_mqtt_ssl")
	en_motion=$(normalize_bool "$new_en_motion")
	en_motion_guard=$(normalize_bool "$new_en_motion_guard")
	en_ircut=$(normalize_bool "$new_en_ircut")
	en_daynight=$(normalize_bool "$new_en_daynight")
	en_privacy=$(normalize_bool "$new_en_privacy")
	en_color=$(normalize_bool "$new_en_color")
	en_ir850=$(normalize_bool "$new_en_ir850")
	en_ir940=$(normalize_bool "$new_en_ir940")
	en_white=$(normalize_bool "$new_en_white")
	en_gain=$(normalize_bool "$new_en_gain")
	en_rssi=$(normalize_bool "$new_en_rssi")
	en_snapshot=$(normalize_bool "$new_en_snapshot")
	en_reboot=$(normalize_bool "$new_en_reboot")
	en_ota=$(normalize_bool "$new_en_ota")

	device_name=$(strip_json_string "$new_device_name")
	device_model=$(strip_json_string "$new_device_model")
	discovery_prefix=$(strip_json_string "$new_discovery_prefix")
	mqtt_host=$(strip_json_string "$new_mqtt_host")
	mqtt_port=$(strip_json_string "$new_mqtt_port")
	mqtt_username=$(strip_json_string "$new_mqtt_username")
	mqtt_password=$(strip_json_string "$new_mqtt_password")
	mqtt_client_id=$(strip_json_string "$new_mqtt_client_id")
	state_interval=$(strip_json_string "$new_state_interval")
	discovery_interval=$(strip_json_string "$new_discovery_interval")

	# Defaults
	[ -n "$discovery_prefix" ] || discovery_prefix="homeassistant"
	mqtt_port=$(normalize_uint_in_range "$mqtt_port" "1883" "1" "65535" "mqtt.port")
	[ -n "$mqtt_client_id" ] || mqtt_client_id="thingino-ha"
	state_interval=$(normalize_uint_in_range "$state_interval" "15" "1" "86400" "state_interval")
	discovery_interval=$(normalize_uint_in_range "$discovery_interval" "3600" "1" "604800" "discovery_interval")

	if [ "$enabled" = "true" ] && [ -z "$mqtt_host" ]; then
		json_error 422 "MQTT host cannot be empty when integration is enabled" "422 Unprocessable Entity"
	fi

	# Write to config
	write_payload_file

	current_json=$(jct "$CONFIG_FILE" get "$DOMAIN" 2>/dev/null)
	new_json=$(effective_ha_config_json)
	if [ "$current_json" = "$new_json" ]; then
		send_json '{"status":"ok","changed":false}'
	fi

	if ! jct "$CONFIG_FILE" import "$TMP_FILE" >/dev/null 2>&1; then
		json_error 500 "Failed to update Home Assistant configuration" "500 Internal Server Error"
	fi

	restart_required=0
	refresh_required=0
	action="none"

	if [ "$old_enabled" != "$enabled" ] ||
		[ "$old_mqtt_host" != "$mqtt_host" ] ||
		[ "$old_mqtt_port" != "$mqtt_port" ] ||
		[ "$old_mqtt_username" != "$mqtt_username" ] ||
		[ "$old_mqtt_password" != "$mqtt_password" ] ||
		[ "$old_mqtt_client_id" != "$mqtt_client_id" ] ||
		[ "$old_mqtt_ssl" != "$mqtt_ssl" ] ||
		[ "$old_state_interval" != "$state_interval" ] ||
		[ "$old_discovery_interval" != "$discovery_interval" ] ||
		[ "$old_discovery_prefix" != "$discovery_prefix" ]; then
		restart_required=1
	fi

	if [ "$old_device_name" != "$device_name" ] ||
		[ "$old_device_model" != "$device_model" ] ||
		[ "$old_en_motion" != "$en_motion" ] ||
		[ "$old_en_motion_guard" != "$en_motion_guard" ] ||
		[ "$old_en_ircut" != "$en_ircut" ] ||
		[ "$old_en_daynight" != "$en_daynight" ] ||
		[ "$old_en_privacy" != "$en_privacy" ] ||
		[ "$old_en_color" != "$en_color" ] ||
		[ "$old_en_ir850" != "$en_ir850" ] ||
		[ "$old_en_ir940" != "$en_ir940" ] ||
		[ "$old_en_white" != "$en_white" ] ||
		[ "$old_en_gain" != "$en_gain" ] ||
		[ "$old_en_rssi" != "$en_rssi" ] ||
		[ "$old_en_snapshot" != "$en_snapshot" ] ||
		[ "$old_en_reboot" != "$en_reboot" ] ||
		[ "$old_en_ota" != "$en_ota" ]; then
		refresh_required=1
	fi

	if [ "$restart_required" = "1" ]; then
		schedule_ha_restart
		action="restart"
	elif [ "$refresh_required" = "1" ] && [ "$enabled" = "true" ]; then
		schedule_ha_refresh
		action="refresh"
	fi

	send_json "{\"status\":\"ok\",\"changed\":true,\"action\":\"${action}\"}"
}

case "$REQUEST_METHOD" in
	GET | "") handle_get ;;
	POST) handle_post ;;
	*) json_error 405 "Method not allowed" "405 Method Not Allowed" ;;
esac
