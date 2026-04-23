#!/bin/sh

# Check authentication
. /var/www/x/auth.sh
require_auth

printf 'Status: 200 OK\r\nContent-Type: application/json\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n'

# Get motor config values
steps_pan_val=$(jct /etc/motors.json get motors.steps_pan 2>/dev/null)
[ -z "$steps_pan_val" ] && steps_pan_val=0
steps_tilt_val=$(jct /etc/motors.json get motors.steps_tilt 2>/dev/null)
[ -z "$steps_tilt_val" ] && steps_tilt_val=0
accel_pan_val=$(jct /etc/motors.json get motors.accel_pan 2>/dev/null)
[ -z "$accel_pan_val" ] && accel_pan_val=0
accel_tilt_val=$(jct /etc/motors.json get motors.accel_tilt 2>/dev/null)
[ -z "$accel_tilt_val" ] && accel_tilt_val=0
motion_driver_val=$(jct /etc/motors.json get motors.motion_driver 2>/dev/null)
[ -z "$motion_driver_val" ] && motion_driver_val=legacy
preview_control_mode_val=$(jct /etc/motors.json get motors.preview_control_mode 2>/dev/null)
[ -z "$preview_control_mode_val" ] && preview_control_mode_val=step
pos_0_val=$(jct /etc/motors.json get motors.pos_0 2>/dev/null)
pos_0_x_val=$(echo $pos_0_val | awk -F',' '{print $1}')
[ -z "$pos_0_x_val" ] && pos_0_x_val=0
pos_0_y_val=$(echo $pos_0_val | awk -F',' '{print $2}')
[ -z "$pos_0_y_val" ] && pos_0_y_val=0

printf '{"steps_pan":%s,"steps_tilt":%s,"accel_pan":%s,"accel_tilt":%s,"motion_driver":"%s","preview_control_mode":"%s","pos_0_x":%s,"pos_0_y":%s}' "$steps_pan_val" "$steps_tilt_val" "$accel_pan_val" "$accel_tilt_val" "$motion_driver_val" "$preview_control_mode_val" "$pos_0_x_val" "$pos_0_y_val"
