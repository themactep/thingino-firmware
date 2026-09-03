#!/bin/sh
# shellcheck disable=SC1091,SC2034,SC3043

# Discover thingino cameras on the local network via mDNS (_thingino._tcp)

. /var/www/x/auth.sh
require_auth

SCAN_SECONDS=4

json_escape() {
	printf '%s' "$1" | sed \
		-e 's/\\/\\\\/g' \
		-e 's/"/\\"/g' \
		-e "s/\r/\\r/g" \
		-e "s/\n/\\n/g"
}

send_json() {
	local payload="$1"
	local status="${2:-200 OK}"
	printf 'Status: %s\n' "$status"
	cat <<EOF
Content-Type: application/json
Cache-Control: no-store
Pragma: no-cache
Connection: close

$payload
EOF
	exit 0
}

json_error() {
	local message="$1"
	local status="${2:-400 Bad Request}"
	send_json "{\"error\": \"$(json_escape "$message")\"}" "$status"
}

local_addresses() {
	ip route show 2>/dev/null | sed -nE 's/.+src ([0-9.]+).+/\1/p'
}

# mquery browse mode prints one line per responder:
#   + hostname._thingino._tcp.local. (192.168.1.42)
# The query window is bounded by -w, so the CGI always terminates.
scan_cameras() {
	mquery -w "$SCAN_SECONDS" _thingino._tcp 2>/dev/null |
		awk -v selfips="$(local_addresses | tr '\n' ' ')" -v selfname="$(hostname)" '
		BEGIN {
			n = split(selfips, a, " ")
			for (i = 1; i <= n; i++) self[a[i]] = 1
		}
		/^\+ / {
			line = substr($0, 3)
			if (!match(line, / \([0-9A-Fa-f.:]+\)$/))
				next
			ip = substr(line, RSTART + 2, RLENGTH - 3)
			name = substr(line, 1, RSTART - 1)
			# Unsolicited announcements of other service types can arrive
			# inside the query window; keep only _thingino._tcp instances.
			if (name !~ /\._thingino\._tcp\.local\.?$/)
				next
			sub(/\._thingino\._tcp\.local\.?$/, "", name)
			if (name == "")
				next
			if (seen[ip]++)
				next
			isself = (ip in self || name == selfname) ? 1 : 0
			print name "\t" ip "\t" isself
		}' | sort -f
}

build_entries() {
	local tab first name ip self
	tab="$(printf '\t')"
	first=1
	while IFS="$tab" read -r name ip self; do
		[ -n "$name" ] || continue
		if [ "$self" = "1" ]; then
			self="true"
		else
			self="false"
		fi
		if [ "$first" -eq 1 ]; then
			first=0
		else
			printf ','
		fi
		printf '{"name": "%s", "ip": "%s", "self": %s}' "$(json_escape "$name")" "$ip" "$self"
	done
}

scan_response() {
	local entries
	entries="$(scan_cameras | build_entries)"
	send_json "{\"ok\": true, \"data\": {\"cameras\": [$entries]}}"
}

case "$REQUEST_METHOD" in
	'' | GET)
		if ! command -v mquery >/dev/null 2>&1; then
			json_error "The mDNS query tool (mquery) is not installed on this camera" "500 Internal Server Error"
		fi
		scan_response
		;;
	POST)
		json_error "Method POST is not allowed." "405 Method Not Allowed"
		;;
	*)
		json_error "Method $REQUEST_METHOD is not allowed." "405 Method Not Allowed"
		;;
esac
