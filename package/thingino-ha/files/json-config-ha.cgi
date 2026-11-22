#!/bin/sh
# shellcheck disable=SC1091,SC2018,SC2019,SC2329,SC3043

# Check authentication
. /var/www/x/auth.sh
require_auth

DOMAIN="ha"
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
	case "$1" in
		"" | null) printf '' ;;
		*) printf '%s' "$1" | sed -e 's/^"//' -e 's/"$//' -e 's/^\\"//' -e 's/\\"$//' ;;
	esac
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

ensure_config() {
	if [ ! -f "$CONFIG_FILE" ]; then
		umask 077
		echo '{}' >"$CONFIG_FILE"
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

	# Top-level fields
	new_enabled=$(jct "$REQ_FILE" get enabled 2>/dev/null)
	new_device_name=$(jct "$REQ_FILE" get device_name 2>/dev/null)
	new_device_model=$(jct "$REQ_FILE" get device_model 2>/dev/null)
	new_discovery_prefix=$(jct "$REQ_FILE" get discovery_prefix 2>/dev/null)
	new_state_interval=$(jct "$REQ_FILE" get state_interval 2>/dev/null)
	new_discovery_interval=$(jct "$REQ_FILE" get discovery_interval 2>/dev/null)
	new_ota_check_interval=$(jct "$REQ_FILE" get ota_check_interval 2>/dev/null)

	# MQTT nested fields
	new_mqtt_host=$(jct "$REQ_FILE" get mqtt.host 2>/dev/null)
	new_mqtt_port=$(jct "$REQ_FILE" get mqtt.port 2>/dev/null)
	new_mqtt_username=$(jct "$REQ_FILE" get mqtt.username 2>/dev/null)
	new_mqtt_password=$(jct "$REQ_FILE" get mqtt.password 2>/dev/null)
	new_mqtt_client_id=$(jct "$REQ_FILE" get mqtt.client_id_prefix 2>/dev/null)
	new_mqtt_ssl=$(jct "$REQ_FILE" get mqtt.use_ssl 2>/dev/null)
	new_mqtt_tls_skip_verify=$(jct "$REQ_FILE" get mqtt.tls_skip_verify 2>/dev/null)

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
	new_en_floodlight=$(jct "$REQ_FILE" get enable_floodlight 2>/dev/null)
	new_en_lamp_socket=$(jct "$REQ_FILE" get enable_lamp_socket 2>/dev/null)
	new_en_gain=$(jct "$REQ_FILE" get enable_gain 2>/dev/null)
	new_en_rssi=$(jct "$REQ_FILE" get enable_rssi 2>/dev/null)
	new_en_snapshot=$(jct "$REQ_FILE" get enable_snapshot 2>/dev/null)
	new_en_reboot=$(jct "$REQ_FILE" get enable_reboot 2>/dev/null)
	new_en_ota=$(jct "$REQ_FILE" get enable_ota 2>/dev/null)
	new_en_doorbell=$(jct "$REQ_FILE" get enable_doorbell 2>/dev/null)
	new_en_firmware_version=$(jct "$REQ_FILE" get enable_firmware_version 2>/dev/null)
	new_en_firmware_timestamp=$(jct "$REQ_FILE" get enable_firmware_timestamp 2>/dev/null)
	new_en_live_view=$(jct "$REQ_FILE" get enable_live_view 2>/dev/null)

	# Normalize
	enabled=$(normalize_bool "$new_enabled") || bad_bool
	mqtt_ssl=$(normalize_bool "$new_mqtt_ssl") || bad_bool
	mqtt_tls_skip_verify=$(normalize_bool "$new_mqtt_tls_skip_verify") || bad_bool
	en_motion=$(normalize_bool "$new_en_motion") || bad_bool
	en_motion_guard=$(normalize_bool "$new_en_motion_guard") || bad_bool
	en_ircut=$(normalize_bool "$new_en_ircut") || bad_bool
	en_daynight=$(normalize_bool "$new_en_daynight") || bad_bool
	en_privacy=$(normalize_bool "$new_en_privacy") || bad_bool
	en_color=$(normalize_bool "$new_en_color") || bad_bool
	en_ir850=$(normalize_bool "$new_en_ir850") || bad_bool
	en_ir940=$(normalize_bool "$new_en_ir940") || bad_bool
	en_white=$(normalize_bool "$new_en_white") || bad_bool
	en_floodlight=$(normalize_bool "$new_en_floodlight") || bad_bool
	en_lamp_socket=$(normalize_bool "$new_en_lamp_socket") || bad_bool
	en_gain=$(normalize_bool "$new_en_gain") || bad_bool
	en_rssi=$(normalize_bool "$new_en_rssi") || bad_bool
	en_snapshot=$(normalize_bool "$new_en_snapshot") || bad_bool
	en_reboot=$(normalize_bool "$new_en_reboot") || bad_bool
	en_ota=$(normalize_bool "$new_en_ota") || bad_bool
	en_doorbell=$(normalize_bool "$new_en_doorbell") || bad_bool
	en_firmware_version=$(normalize_bool "$new_en_firmware_version") || bad_bool
	en_firmware_timestamp=$(normalize_bool "$new_en_firmware_timestamp") || bad_bool
	en_live_view=$(normalize_bool "$new_en_live_view") || bad_bool

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
	ota_check_interval=$(strip_json_string "$new_ota_check_interval")

	# Defaults
	[ -n "$discovery_prefix" ] || discovery_prefix="homeassistant"
	[ -n "$mqtt_port" ] || mqtt_port="1883"
	[ -n "$mqtt_client_id" ] || mqtt_client_id="thingino-ha"
	[ -n "$state_interval" ] || state_interval="15"
	[ -n "$discovery_interval" ] || discovery_interval="3600"
	[ -n "$ota_check_interval" ] || ota_check_interval="21600"

	if [ "$enabled" = "true" ] && [ -z "$mqtt_host" ]; then
		json_error 422 "MQTT host cannot be empty when integration is enabled" "422 Unprocessable Entity"
	fi

	# Write to config
	TMP_FILE=$(mktemp /tmp/${DOMAIN}.XXXXXX)
	echo '{}' >"$TMP_FILE"

	jct "$TMP_FILE" set "${DOMAIN}.enabled" "$enabled" >/dev/null 2>&1
	jct "$TMP_FILE" set "${DOMAIN}.device_name" "$device_name" >/dev/null 2>&1
	jct "$TMP_FILE" set "${DOMAIN}.device_model" "$device_model" >/dev/null 2>&1
	jct "$TMP_FILE" set "${DOMAIN}.discovery_prefix" "$discovery_prefix" >/dev/null 2>&1
	jct "$TMP_FILE" set "${DOMAIN}.state_interval" "$state_interval" >/dev/null 2>&1
	jct "$TMP_FILE" set "${DOMAIN}.discovery_interval" "$discovery_interval" >/dev/null 2>&1
	jct "$TMP_FILE" set "${DOMAIN}.ota_check_interval" "$ota_check_interval" >/dev/null 2>&1
	jct "$TMP_FILE" set "${DOMAIN}.mqtt.host" "$mqtt_host" >/dev/null 2>&1
	jct "$TMP_FILE" set "${DOMAIN}.mqtt.port" "$mqtt_port" >/dev/null 2>&1
	jct "$TMP_FILE" set "${DOMAIN}.mqtt.username" "$mqtt_username" >/dev/null 2>&1
	jct "$TMP_FILE" set "${DOMAIN}.mqtt.password" "$mqtt_password" >/dev/null 2>&1
	jct "$TMP_FILE" set "${DOMAIN}.mqtt.client_id_prefix" "$mqtt_client_id" >/dev/null 2>&1
	jct "$TMP_FILE" set "${DOMAIN}.mqtt.use_ssl" "$mqtt_ssl" >/dev/null 2>&1
	jct "$TMP_FILE" set "${DOMAIN}.mqtt.tls_skip_verify" "$mqtt_tls_skip_verify" >/dev/null 2>&1
	jct "$TMP_FILE" set "${DOMAIN}.enable_motion" "$en_motion" >/dev/null 2>&1
	jct "$TMP_FILE" set "${DOMAIN}.enable_motion_guard" "$en_motion_guard" >/dev/null 2>&1
	jct "$TMP_FILE" set "${DOMAIN}.enable_ircut" "$en_ircut" >/dev/null 2>&1
	jct "$TMP_FILE" set "${DOMAIN}.enable_daynight" "$en_daynight" >/dev/null 2>&1
	jct "$TMP_FILE" set "${DOMAIN}.enable_privacy" "$en_privacy" >/dev/null 2>&1
	jct "$TMP_FILE" set "${DOMAIN}.enable_color" "$en_color" >/dev/null 2>&1
	jct "$TMP_FILE" set "${DOMAIN}.enable_ir850" "$en_ir850" >/dev/null 2>&1
	jct "$TMP_FILE" set "${DOMAIN}.enable_ir940" "$en_ir940" >/dev/null 2>&1
	jct "$TMP_FILE" set "${DOMAIN}.enable_white_light" "$en_white" >/dev/null 2>&1
	jct "$TMP_FILE" set "${DOMAIN}.enable_floodlight" "$en_floodlight" >/dev/null 2>&1
	if command -v lamp_socket_ctl >/dev/null 2>&1; then
		jct "$TMP_FILE" set "${DOMAIN}.enable_lamp_socket" "$en_lamp_socket" >/dev/null 2>&1
	fi
	jct "$TMP_FILE" set "${DOMAIN}.enable_gain" "$en_gain" >/dev/null 2>&1
	jct "$TMP_FILE" set "${DOMAIN}.enable_rssi" "$en_rssi" >/dev/null 2>&1
	jct "$TMP_FILE" set "${DOMAIN}.enable_snapshot" "$en_snapshot" >/dev/null 2>&1
	jct "$TMP_FILE" set "${DOMAIN}.enable_reboot" "$en_reboot" >/dev/null 2>&1
	jct "$TMP_FILE" set "${DOMAIN}.enable_ota" "$en_ota" >/dev/null 2>&1
	jct "$TMP_FILE" set "${DOMAIN}.enable_doorbell" "$en_doorbell" >/dev/null 2>&1
	jct "$TMP_FILE" set "${DOMAIN}.enable_firmware_version" "$en_firmware_version" >/dev/null 2>&1
	jct "$TMP_FILE" set "${DOMAIN}.enable_firmware_timestamp" "$en_firmware_timestamp" >/dev/null 2>&1
	jct "$TMP_FILE" set "${DOMAIN}.enable_live_view" "$en_live_view" >/dev/null 2>&1

	jct "$CONFIG_FILE" import "$TMP_FILE" >/dev/null 2>&1

	# Restart ha-daemon to pick up new settings
	/etc/init.d/S93ha restart >/dev/null 2>&1 &

	send_json '{"status":"ok"}'
}

case "$REQUEST_METHOD" in
	GET | "") handle_get ;;
	POST) handle_post ;;
	*) json_error 405 "Method not allowed" "405 Method Not Allowed" ;;
esac
