#!/bin/sh
# shellcheck disable=SC1091,SC2034,SC3043

# Discover thingino cameras on the local network via mDNS (_thingino._tcp)

. /var/www/x/auth.sh
require_auth

SCAN_SECONDS=3
SCAN_ROUNDS=2
TXT_SECONDS=2
TXT_BATCH=4
CACHE_FILE="/tmp/json-cameras.cache"

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
#
# mquery's -w only stops the event loop after select() returns.  Once the
# query retries are exhausted libmdnsd schedules its next wakeup a day out
# (its GC timer), so a -w longer than the three-second retry schedule makes
# mquery block until the next mDNS packet instead of exiting.  Keep each
# pass at three seconds and run a couple of passes instead: mDNS replies
# are UDP and get dropped on busy Wi-Fi segments, so one pass is not
# enough to see the whole fleet.
scan_cameras() {
	local rounds i
	rounds="${SCAN_ROUNDS:-2}"
	i=0
	while [ "$i" -lt "$rounds" ]; do
		mquery -w "$SCAN_SECONDS" _thingino._tcp 2>/dev/null
		i=$((i + 1))
	done
}

normalize_cameras() {
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
			fqdn = substr(line, 1, RSTART - 1)
			# Unsolicited announcements of other service types can arrive
			# inside the query window; keep only _thingino._tcp instances.
			if (fqdn !~ /\._thingino\._tcp\.local\.?$/)
				next
			name = fqdn
			sub(/\._thingino\._tcp\.local\.?$/, "", name)
			if (name == "")
				next
			if (seen[ip]++)
				next
			isself = (ip in self || name == selfname) ? 1 : 0
			print name "\t" ip "\t" fqdn "\t" isself
		}'
}

resolve_camera() {
	local name="$1" ip="$2" fqdn="$3" self="$4" txt field key val model version streamer

	model=""
	version=""
	streamer=""
	txt="$(mquery -t 16 -w "$TXT_SECONDS" "$fqdn" </dev/null 2>/dev/null |
		sed -n 's/^TXT .* seconds: //p' | head -n 1)"
	if [ -n "$txt" ]; then
		# shellcheck disable=SC2086
		for field in $txt; do
			key="${field%%=*}"
			val="${field#*=}"
			case "$key" in
				product) model="$val" ;;
				version) version="$val" ;;
				streamer) streamer="$val" ;;
			esac
		done
	fi

	printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$name" "$ip" "$self" "$model" "$version" "$streamer"
}

build_entries() {
	local tab tmpdir i n first name ip fqdn self model version streamer
	tab="$(printf '\t')"
	tmpdir="$(mktemp -d)"
	i=0
	while IFS="$tab" read -r name ip fqdn self; do
		[ -n "$name" ] || continue
		i=$((i + 1))
		resolve_camera "$name" "$ip" "$fqdn" "$self" >"$tmpdir/$i" </dev/null &
		if [ $((i % TXT_BATCH)) -eq 0 ]; then
			wait
		fi
	done
	wait

	first=1
	n=1
	while [ "$n" -le "$i" ]; do
		if [ -s "$tmpdir/$n" ]; then
			IFS="$tab" read -r name ip self model version streamer <"$tmpdir/$n"
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
			printf '{"name": "%s", "ip": "%s", "self": %s, "model": "%s", "version": "%s", "streamer": "%s"}' \
				"$(json_escape "$name")" "$ip" "$self" \
				"$(json_escape "$model")" "$(json_escape "$version")" "$(json_escape "$streamer")"
		fi
		n=$((n + 1))
	done

	rm -rf "$tmpdir"
}

build_response() {
	local browse_file entries
	browse_file="$(mktemp)"
	scan_cameras >"$browse_file"
	entries="$(normalize_cameras <"$browse_file" | sort -f | build_entries)"
	rm -f "$browse_file"
	printf '{"ok": true, "data": {"cameras": [%s]}}' "$entries"
}

scan_response() {
	local payload tmpfile
	payload="$(build_response)"
	tmpfile="${CACHE_FILE}.$$"
	printf '%s' "$payload" >"$tmpfile"
	mv "$tmpfile" "$CACHE_FILE"
	send_json "$payload"
}

cached_response() {
	if [ -r "$CACHE_FILE" ]; then
		send_json "$(cat "$CACHE_FILE")"
	fi
	scan_response
}

want_refresh() {
	case "$QUERY_STRING" in
		*refresh*) return 0 ;;
	esac
	return 1
}

case "$REQUEST_METHOD" in
	'' | GET)
		if ! command -v mquery >/dev/null 2>&1; then
			json_error "The mDNS query tool (mquery) is not installed on this camera" "500 Internal Server Error"
		fi
		if want_refresh; then
			scan_response
		else
			cached_response
		fi
		;;
	POST)
		json_error "Method POST is not allowed." "405 Method Not Allowed"
		;;
	*)
		json_error "Method $REQUEST_METHOD is not allowed." "405 Method Not Allowed"
		;;
esac
