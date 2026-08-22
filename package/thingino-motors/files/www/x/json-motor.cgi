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
[ -n "$order" ] && order=$(urldecode "$order")

json_escape() {
	printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

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
			presets_json="$presets_json{\"number\":$pnum,\"name\":\"$(json_escape "$pname")\",\"x\":$px,\"y\":$py}"
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
	pu)
		# Update an existing preset's name and coordinates
		[ -n "$n" ] || json_error "preset-number-required"
		[ -n "$name" ] || json_error "preset-name-required"
		case "$x" in
			'' | *[!0-9]*) json_error "preset-x-invalid" ;;
		esac
		case "$y" in
			'' | *[!0-9]*) json_error "preset-y-invalid" ;;
		esac
		ptz_presets -a "$n" "$name" "$x" "$y" >/dev/null 2>&1 || json_error "preset-update-failed"
		json_ok "{\"status\":\"preset $n updated\"}"
		;;
	po)
		# Reorder presets: order is a comma-separated list of preset numbers.
		# Presets are renumbered 0..N-1 in the new order; empty slots are
		# kept at the end so the file's slot count is preserved.
		[ -n "$order" ] || json_error "preset-order-required"

		tmp=$(mktemp)

		# Count slots (non-comment lines) to preserve the file's slot count.
		slots=0
		while IFS= read -r line; do
			case "$line" in
				\#* | '') continue ;;
			esac
			slots=$((slots + 1))
		done </etc/ptz_presets.conf 2>/dev/null

		# Preserve comment/header lines verbatim at the top.
		while IFS= read -r line; do
			case "$line" in
				\#*) printf '%s\n' "$line" >>"$tmp" ;;
			esac
		done </etc/ptz_presets.conf 2>/dev/null

		newnum=0

		# Emit presets in the requested order, renumbered sequentially.
		oldifs=$IFS
		IFS=','
		for pn in $order; do
			IFS=$oldifs
			case "$pn" in
				'' | *[!0-9]*) continue ;;
			esac
			line=$(grep "^$pn=" /etc/ptz_presets.conf 2>/dev/null | head -n1)
			if [ -n "$line" ]; then
				printf '%s=%s\n' "$newnum" "${line#*=}" >>"$tmp"
				newnum=$((newnum + 1))
			fi
			IFS=','
		done
		IFS=$oldifs

		# Append populated presets not in the order list, renumbered.
		while IFS= read -r line; do
			case "$line" in
				\#* | '') continue ;;
			esac
			pn=${line%%=*}
			vals=${line#*=}
			case "$vals" in
				,,*) continue ;;
			esac
			case ",$order," in
				*",$pn,"*) continue ;;
			esac
			printf '%s=%s\n' "$newnum" "$vals" >>"$tmp"
			newnum=$((newnum + 1))
		done </etc/ptz_presets.conf 2>/dev/null

		# Pad with empty slots to preserve the original slot count.
		while [ "$newnum" -lt "$slots" ]; do
			printf '%s=,,\n' "$newnum" >>"$tmp"
			newnum=$((newnum + 1))
		done

		mv "$tmp" /etc/ptz_presets.conf
		json_ok "{\"status\":\"presets reordered\"}"
		;;
	*)
		json_error "motors-command-unsupported"
		;;
esac

emit_status
