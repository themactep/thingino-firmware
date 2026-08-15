#!/bin/sh
# shellcheck disable=SC2154  # target/state/service etc. are assigned by the eval of QUERY_STRING below

# Check authentication
# shellcheck disable=SC1091  # auth.sh is installed on the camera, not in the build tree
. /var/www/x/auth.sh
require_auth

http_200() {
	printf 'Status: 200 OK\r\n'
}

# shellcheck disable=SC2329  # kept as a shared error helper for parity with the other json-* CGIs
http_400() {
	printf 'Status: 400 Bad Request\r\n'
}

http_412() {
	printf 'Status: 412 Precondition Failed\r\n'
}

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
	printf '{"error":{"code":412,"message":"%s"}}
' "$1"
	exit 0
}

json_ok() {
	http_200
	json_header
	case $1 in
		\{*)
			printf '{"code":200,"result":"success","message":%s}\n' "$1"
			;;
		*)
			printf '{"code":200,"result":"success","message":"%s"}\n' "$1"
			;;
	esac
	exit 0
}

agent_set_bool() {
	path=$1
	value=$2
	tmp=$(mktemp /tmp/json-motion.XXXXXX) || return 1
	printf '{"enabled":%s}\n' "$value" >"$tmp"
	thingino-agentctl set-setting "$path" "$tmp" >/dev/null 2>&1
	rc=$?
	rm -f "$tmp"
	return $rc
}

agent_set_int() {
	path=$1
	key=$2
	value=$3
	tmp=$(mktemp /tmp/json-motion.XXXXXX) || return 1
	printf '{"%s":%s}\n' "$key" "$value" >"$tmp"
	thingino-agentctl set-setting "$path" "$tmp" >/dev/null 2>&1
	rc=$?
	rm -f "$tmp"
	return $rc
}

# shellcheck disable=SC2046  # eval needs the query string's wordsplit assignment list
[ -n "$QUERY_STRING" ] && eval $(echo "$QUERY_STRING" | sed "s/&/;/g")

case "$target" in
	enabled)
		case "$state" in
			true | false)
				if command -v thingino-agentctl >/dev/null 2>&1; then
					agent_set_bool motion/enabled "$state" || json_error "agent motion set failed"
				else
					jct /etc/prudynt.json set "motion.$target" "$state"
				fi
				json_ok "{\"target\":\"$target\",\"status\":$state}"
				;;
			*)
				json_error "state missing"
				;;
		esac
		;;
	send2email | send2ftp | send2gphotos | send2mqtt | send2ntfy | send2storage | send2telegram | send2webhook)
		case "$state" in
			true | false)
				service=${target#send2}
				if command -v thingino-agentctl >/dev/null 2>&1; then
					agent_set_bool "motion/outputs/send2/$service" "$state" || json_error "agent motion output set failed"
				else
					jct /etc/prudynt.json set "motion.$target" "$state"
				fi
				json_ok "{\"target\":\"$target\",\"status\":$state}"
				;;
			*)
				json_error "state missing"
				;;
		esac
		;;
	sensitivity)
		if command -v thingino-agentctl >/dev/null 2>&1; then
			agent_set_int motion/sensitivity sensitivity "$state" || json_error "agent sensitivity set failed"
		else
			jct /etc/prudynt.json set "motion.$target" "$state"
		fi
		json_ok "{\"target\":\"$target\",\"state\":$state}"
		;;
	cooldown_time)
		if command -v thingino-agentctl >/dev/null 2>&1; then
			agent_set_int motion/cooldown-time cooldown_time "$state" || json_error "agent cooldown set failed"
		else
			jct /etc/prudynt.json set "motion.$target" "$state"
		fi
		json_ok "{\"target\":\"$target\",\"state\":$state}"
		;;
	video_length)
		jct /etc/prudynt.json set "motion.$target" "$state" 2>/dev/null || true
		json_ok "{\"target\":\"$target\",\"state\":$state}"
		;;
	*)
		json_error "target missing"
		;;
esac
