#!/bin/sh
# shellcheck disable=SC1091,SC2086,SC2154,SC3043

# Check authentication
. /var/www/x/auth.sh
require_auth

MOTORS_CONFIG="/etc/thingino.json"

# Get motor config values
steps_pan_val=$(jct "$MOTORS_CONFIG" get motors.steps_pan 2>/dev/null)
[ -z "$steps_pan_val" ] && steps_pan_val=0
steps_tilt_val=$(jct "$MOTORS_CONFIG" get motors.steps_tilt 2>/dev/null)
[ -z "$steps_tilt_val" ] && steps_tilt_val=0
speed_pan_val=$(jct "$MOTORS_CONFIG" get motors.speed_pan 2>/dev/null)
[ -z "$speed_pan_val" ] && speed_pan_val=0
speed_tilt_val=$(jct "$MOTORS_CONFIG" get motors.speed_tilt 2>/dev/null)
[ -z "$speed_tilt_val" ] && speed_tilt_val=0
accel_pan_val=$(jct "$MOTORS_CONFIG" get motors.accel_pan 2>/dev/null)
[ -z "$accel_pan_val" ] && accel_pan_val=0
accel_tilt_val=$(jct "$MOTORS_CONFIG" get motors.accel_tilt 2>/dev/null)
[ -z "$accel_tilt_val" ] && accel_tilt_val=0
motion_driver_val=$(jct "$MOTORS_CONFIG" get motors.motion_driver 2>/dev/null)
[ -z "$motion_driver_val" ] && motion_driver_val=legacy
preview_control_mode_val=$(jct "$MOTORS_CONFIG" get motors.preview_control_mode 2>/dev/null)
[ -z "$preview_control_mode_val" ] && preview_control_mode_val=step
pos_0_x_val=$(jct "$MOTORS_CONFIG" get motors.presets.0.x 2>/dev/null)
[ -z "$pos_0_x_val" ] && pos_0_x_val=0
pos_0_y_val=$(jct "$MOTORS_CONFIG" get motors.presets.0.y 2>/dev/null)
[ -z "$pos_0_y_val" ] && pos_0_y_val=0

read_post_data() {
	if [ -n "$CONTENT_LENGTH" ] && [ "$CONTENT_LENGTH" -gt 0 ]; then
		body=$(dd bs=1 count="$CONTENT_LENGTH" 2>/dev/null)
		eval "$(printf '%s' "$body" | awk -F'&' '{
      for (i=1; i<=NF; i++) {
        split($i, kv, "=")
        key = kv[1]
        value = kv[2]
        gsub(/\+/, " ", value)
        gsub(/%([0-9A-Fa-f]{2})/, "\\x\\1", value)
        printf "POST_%s=\"%s\"\n", key, value
      }
    }')"
	fi
}

if [ "$REQUEST_METHOD" = "POST" ]; then
	read_post_data

	changed=0

	case "$POST_preview_control_mode" in
		step | continuous)
			if [ "$POST_preview_control_mode" != "$preview_control_mode_val" ]; then
				jct "$MOTORS_CONFIG" set motors.preview_control_mode "$POST_preview_control_mode" >/dev/null 2>&1
				preview_control_mode_val=$POST_preview_control_mode
				changed=1
			fi
			;;
	esac

	case "$POST_speed_pan" in
		'' | *[!0-9]*) ;;
		*)
			if [ "$POST_speed_pan" != "$speed_pan_val" ]; then
				jct "$MOTORS_CONFIG" set motors.speed_pan "$POST_speed_pan" >/dev/null 2>&1
				speed_pan_val=$POST_speed_pan
				changed=1
			fi
			;;
	esac

	case "$POST_speed_tilt" in
		'' | *[!0-9]*) ;;
		*)
			if [ "$POST_speed_tilt" != "$speed_tilt_val" ]; then
				jct "$MOTORS_CONFIG" set motors.speed_tilt "$POST_speed_tilt" >/dev/null 2>&1
				speed_tilt_val=$POST_speed_tilt
				changed=1
			fi
			;;
	esac

	[ "$changed" = 1 ] && motors -R >/dev/null 2>&1
fi

printf 'Status: 200 OK\r\nContent-Type: application/json\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n'

printf '{"steps_pan":%s,"steps_tilt":%s,"speed_pan":%s,"speed_tilt":%s,"accel_pan":%s,"accel_tilt":%s,"motion_driver":"%s","preview_control_mode":"%s","pos_0_x":%s,"pos_0_y":%s}' "$steps_pan_val" "$steps_tilt_val" "$speed_pan_val" "$speed_tilt_val" "$accel_pan_val" "$accel_tilt_val" "$motion_driver_val" "$preview_control_mode_val" "$pos_0_x_val" "$pos_0_y_val"
