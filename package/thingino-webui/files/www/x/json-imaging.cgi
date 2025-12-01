#!/bin/sh
# shellcheck disable=SC2039
. ./_json.sh

STATE_FILE="/run/prudynt/imaging.json"
IMAGING_FIFO="/run/prudynt/imagingctl"
FIELDS="brightness contrast saturation sharpness"

urldecode() {
	local i="${*//+/ }"
	echo -e "${i//%/\\x}"
}

is_number() {
	printf "%s" "$1" | grep -Eq '^[-+]?[0-9]+(\.[0-9]+)?$'
}

field_attr() {
	local field="$1" attr="$2"
	jct "$STATE_FILE" get "fields.${field}.${attr}" 2>/dev/null | tr -d '"' | tr -d '\n' | tr -d '\r'
}

collect_fields() {
	[ -r "$STATE_FILE" ] || return 1
	local first=1 field value min max norm
	printf '{'
	for field in $FIELDS; do
		value=$(field_attr "$field" value)
		min=$(field_attr "$field" min)
		max=$(field_attr "$field" max)
		norm=$(field_attr "$field" normalized)
		[ -z "$value" ] && continue
		[ -z "$norm" ] && norm="0"
		if [ $first -eq 0 ]; then
			printf ','
		fi
		printf '"%s":{"value":%s,"min":%s,"max":%s,"normalized":%s}' \
			"$field" "$value" "$min" "$max" "$norm"
		first=0
	done
	printf '}'
	return 0
}

read_fields_with_retry() {
	local attempt=0 result
	while [ $attempt -lt 5 ]; do
		result=$(collect_fields) && { echo "$result"; return 0; }
		sleep 0.1
		attempt=$((attempt + 1))
	done
	return 1
}

normalize_value() {
	local field="$1" raw="$2" min max
	min=$(field_attr "$field" min)
	max=$(field_attr "$field" max)
	[ -z "$min" ] && return 1
	[ -z "$max" ] && return 1
	awk -v v="$raw" -v mn="$min" -v mx="$max" 'BEGIN {
		if (mx <= mn) {
			print "0.0000";
			exit
		}
		if (v < mn) {
			v = mn;
		} else if (v > mx) {
			v = mx;
		}
		printf "%.4f", (v - mn) / (mx - mn);
	}'
}

apply_updates() {
	local payload="SET" changed=0 field raw norm
	for field in $FIELDS; do
		eval "raw=\${$field}"
		[ -z "$raw" ] && continue
		if ! is_number "$raw"; then
			json_error "invalid value for $field"
		fi
		norm=$(normalize_value "$field" "$raw") || json_error "missing range for $field"
		payload="$payload $field=$norm"
		changed=1
	done
	[ $changed -eq 1 ] || json_error "no imaging parameters provided"
	if ! printf '%s\n' "$payload" > "$IMAGING_FIFO"; then
		json_error "failed to send imaging command"
	fi
	sleep 0.1
	local fields_json
	fields_json=$(read_fields_with_retry) || json_error "imaging state unavailable"
	json_ok "{\"fields\":$fields_json}"
}

handle_read() {
	local fields_json
	fields_json=$(read_fields_with_retry) || json_error "imaging state unavailable"
	json_ok "{\"fields\":$fields_json}"
}

parse_body() {
	local data="$1"
	[ -z "$data" ] && return
	eval "$(echo "$data" | sed 's/&/;/g')"
}

if [ "$REQUEST_METHOD" = "POST" ] && [ -z "$QUERY_STRING" ]; then
	read -r body
	QUERY_STRING="$body"
fi

[ -n "$QUERY_STRING" ] && parse_body "$QUERY_STRING"

for param in cmd $FIELDS; do
	eval "value=\${$param}"
	[ -n "$value" ] && eval "$param=\"$(urldecode "$value")\""
done

cmd="${cmd:-read}"

case "$cmd" in
	read)
		handle_read
		;;
	set)
		apply_updates
		;;
	*)
		json_error "unknown command"
		;;
esac
