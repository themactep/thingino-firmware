#!/bin/sh
# shellcheck disable=SC1091,SC2046,SC2329,SC3043

# Check authentication
. /var/www/x/auth.sh
require_auth

http_200() {
	printf 'Status: 200 OK\r\n'
}

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
	if [ "{" = "$(printf '%.1s' "$1")" ]; then
		printf '{"code":200,"result":"success","message":%s}
' "$1"
	else
		printf '{"code":200,"result":"success","message":"%s"}
' "$1"
	fi
	exit 0
}

[ -n "$QUERY_STRING" ] && eval $(echo "$QUERY_STRING" | sed "s/&/;/g")

# URL-decode string params (name, n) — the rest are numeric/single char.
urldecode() {
	printf '%b' "$(echo "$1" | sed 's/+/ /g; s/%\([0-9A-Fa-f][0-9A-Fa-f]\)/\\x\1/g')"
}
[ -n "$name" ] && name=$(urldecode "$name")
[ -n "$n" ] && n=$(urldecode "$n")

[ -z "$x" ] && x=0
[ -z "$y" ] && y=0
[ -z "$d" ] && d="g"

emit_status() {
	local payload
	if ! payload=$(motors -j 2>/dev/null); then
		json_error "motors-status-failed"
	fi
	json_ok "$payload"
}

case "$d" in
	g) motors -d g -x "$x" -y "$y" >/dev/null ;;
	r) motors -r >/dev/null ;;
	h | x) motors -d h -x "$x" -y "$y" >/dev/null ;;
	s) motors -d s >/dev/null ;;
	b) motors -d b >/dev/null ;;
	i)
		payload=$(motors -i 2>/dev/null) || json_error "motors-initial-failed"
		json_ok "$payload"
		;;
	j)
		payload=$(motors -j 2>/dev/null) || json_error "motors-status-failed"
		json_ok "$payload"
		;;
	pg)
		# List PTZ presets from /etc/ptz_presets.conf: [{"number":N,"name":"..","x":N,"y":N}]
		presets_json="["
		first=1
		while IFS='=' read -r pnum rest; do
			case "$pnum" in
				\#* | "") continue ;;
				*[!0-9]*) continue ;;
			esac
			pname="${rest%%,*}"
			pcoords="${rest#*,}"
			px="${pcoords%%,*}"
			py="${pcoords#*,}"
			[ -n "$px" ] && [ -n "$py" ] || continue
			[ "$first" = "1" ] || presets_json="$presets_json,"
			first=0
			presets_json="$presets_json{\"number\":$pnum,\"name\":\"$pname\",\"x\":$px,\"y\":$py}"
		done </etc/ptz_presets.conf 2>/dev/null
		presets_json="$presets_json]"
		json_ok "{\"presets\":$presets_json}"
		;;
	ps)
		# Save current motor position as a preset (auto slot)
		[ -n "$name" ] || json_error "preset-name-required"
		output=$(ptz_presets -a -1 "$name" 2>&1) || json_error "preset-save-failed"
		json_ok "{\"status\":\"$output\"}"
		;;
	pr)
		# Move to a preset
		[ -n "$n" ] || json_error "preset-number-required"
		output=$(ptz_presets "$n" 2>&1) || json_error "preset-run-failed"
		json_ok "{\"status\":\"preset $n run\"}"
		;;
	pd)
		# Delete a preset
		[ -n "$n" ] || json_error "preset-number-required"
		ptz_presets -r "$n" >/dev/null 2>&1
		json_ok "{\"status\":\"preset $n deleted\"}"
		;;
	*)
		json_error "motors-command-unsupported"
		;;
esac

emit_status
