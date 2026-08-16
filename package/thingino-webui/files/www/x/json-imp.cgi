#!/bin/sh
# shellcheck disable=SC1083,SC1091,SC2086,SC2119,SC2120,SC2329
# shellcheck disable=SC2039
# Day/night control. With daynightd (prudynt images) this writes to
# /etc/thingino.json and notifies daynightd via SIGHUP; with Raptor
# the ric daemon owns day/night, so commands go through the raptor
# wrapper scripts and no config write or reload is needed.

. /var/www/x/auth.sh
require_auth

http_200() { printf 'Status: 200 OK\r\n'; }
http_400() { printf 'Status: 400 Bad Request\r\n'; }
http_412() { printf 'Status: 412 Precondition Failed\r\n'; }

json_header() {
	printf 'Content-Type: application/json\r\n'
	printf 'Pragma: no-cache\r\n'
	printf 'Expires: %s\r\n' "$(TZ=GMT0 date +'%a, %d %b %Y %T %Z')"
	printf 'Etag: "%s"\r\n' "$(cat /proc/sys/kernel/random/uuid)"
	printf 'Connection: close\r\n'
	printf '\r\n'
}

json_error() {
	http_412
	json_header
	printf '{"error":{"code":412,"message":"%s"}}\n' "$1"
	exit 0
}

json_ok() {
	http_200
	json_header
	case "$1" in
		{*) printf '{"code":200,"result":"success","message":%s}\n' "$1" ;;
		*) printf '{"code":200,"result":"success","message":"%s"\n' "$1" ;;
	esac
	exit 0
}

bad_request() {
	http_400
	echo
	echo "$1"
	exit 1
}

daynightd_reload() {
	if [ -f /run/daynightd.pid ]; then
		kill -HUP "$(cat /run/daynightd.pid)" 2>/dev/null || true
	fi
}

# Raptor images have raptorctl and ric applies mode changes
# immediately, so those branches skip the daynightd config keys and
# the reload. daynightd can be selected on raptor images too (it
# replaces ric as the day/night engine), so its presence wins.
is_raptor() {
	command -v raptorctl >/dev/null 2>&1 &&
		! command -v daynightd >/dev/null 2>&1
}

CONFIG="${THINGINO_CONFIG:-/etc/thingino.json}"

# Read POST data
read -r POST_DATA

cmd=$(printf '%s' "$POST_DATA" | awk -F'"' '/"cmd"/{for(i=1;i<=NF;i++){if($i=="cmd"){print $(i+2); exit}}}')
val=$(printf '%s' "$POST_DATA" | sed -n 's/.*"val"[[:space:]]*:[[:space:]]*"\{0,1\}\([^",}]*\).*/\1/p')

[ -z "$cmd" ] && bad_request "missing required parameter cmd"
[ -z "$val" ] && bad_request "missing required parameter val"

case "$cmd" in
	auto)
		case "$val" in
			1 | true | on)
				if is_raptor; then
					/usr/sbin/daynight auto >/dev/null 2>&1
				else
					# Enable photosensing, clear force mode
					jct "$CONFIG" set daynight.enabled true >/dev/null 2>&1
					jct "$CONFIG" set daynight.force_mode "" >/dev/null 2>&1
					daynightd_reload
				fi
				;;
			0 | false | off)
				if is_raptor; then
					/usr/sbin/daynight day >/dev/null 2>&1
				else
					# Disable photosensing, force day mode
					jct "$CONFIG" set daynight.enabled false >/dev/null 2>&1
					jct "$CONFIG" set daynight.force_mode day >/dev/null 2>&1
					daynightd_reload
				fi
				;;
		esac
		;;
	color)
		# Direct ISP color mode toggle
		if command -v prudyntctl >/dev/null 2>&1; then
			echo "{\"image\":{\"running_mode\": $val}}" | prudyntctl json - >/dev/null 2>&1
		elif command -v color >/dev/null 2>&1; then
			color "$val" >/dev/null 2>&1
		fi
		;;
	daynight)
		# Direct day/night force — disables photosensing
		if is_raptor; then
			# ric mode day/night is itself the force
			/usr/sbin/daynight "$val" >/dev/null 2>&1
		else
			jct "$CONFIG" set daynight.enabled false >/dev/null 2>&1
			jct "$CONFIG" set daynight.force_mode "$val" >/dev/null 2>&1
			/sbin/daynight "$val" >/dev/null 2>&1
			daynightd_reload
		fi
		;;
	ir850 | ir940 | white)
		if is_raptor; then
			# Manual light control; transient under ric auto (the
			# next transition reasserts the mode)
			light $cmd $val
		else
			jct "$CONFIG" set daynight.enabled false >/dev/null 2>&1
			jct "$CONFIG" set daynight.force_mode night >/dev/null 2>&1
			daynightd_reload
			light $cmd $val
		fi
		;;
	ircut)
		if is_raptor; then
			ircut $val >/dev/null
		else
			jct "$CONFIG" set daynight.enabled false >/dev/null 2>&1
			ircut $val >/dev/null
			daynightd_reload
		fi
		;;
esac

json_ok
