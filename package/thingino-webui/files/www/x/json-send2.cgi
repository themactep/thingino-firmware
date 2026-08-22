#!/bin/sh
# shellcheck disable=SC3043  # busybox ash supports local; POSIX does not define it

# Check authentication
# shellcheck disable=SC1091  # auth.sh is installed on the camera, not in the build tree
. /var/www/x/auth.sh
require_auth

config_file="/etc/send2.json"
prudynt_config="/etc/prudynt.json"

send_json_response() {
	printf 'Content-Type: application/json\r\nConnection: close\r\n\r\n'
	printf '%s' "$1"
}

send_error() {
	send_json_response "{\"error\":{\"message\":\"$1\"}}"
}

default_domain_config() {
	case "$1" in
		gotify)
			cat <<'EOF'
{"url":"","token":"","title":"Thingino Camera","message":"Motion detected at %Y-%m-%d %H:%M:%S","extras":"","priority":5,"send_photo":false,"send_video":false}
EOF
			;;
		*)
			echo '{}'
			;;
	esac
}

# GET - Load configuration
if [ "$REQUEST_METHOD" = "GET" ]; then
	# Prefer agent motion enable; fall back to prudynt.json
	motion_data=
	if command -v agentctl >/dev/null 2>&1; then
		enabled=$(agentctl get-setting motion/enabled 2>/dev/null | sed -n 's/.*"enabled"[[:space:]]*:[[:space:]]*\(true\|false\).*/\1/p' | head -n 1)
		[ -n "$enabled" ] && motion_data="{\"enabled\":$enabled}"
	fi
	if [ -z "$motion_data" ]; then
		if [ -f "$prudynt_config" ]; then
			motion_data=$(jct "$prudynt_config" get motion 2>/dev/null || echo '{}')
		else
			motion_data='{}'
		fi
	fi

	# Helper to safely get config values
	get_domain_config() {
		local domain="$1"
		local value=""
		if [ -f "$config_file" ]; then
			value=$(jct "$config_file" get "$domain" 2>/dev/null)
		fi

		if [ -n "$value" ] && [ "$value" != "null" ]; then
			echo "$value"
		else
			default_domain_config "$domain"
		fi
	}

	# Combine into response
	printf 'Content-Type: application/json\r\nConnection: close\r\n\r\n'
	cat <<EOF
{
  "motion": $motion_data,
  "email": $(get_domain_config email),
  "ftp": $(get_domain_config ftp),
  "telegram": $(get_domain_config telegram),
  "gotify": $(get_domain_config gotify),
  "mqtt": $(get_domain_config mqtt),
  "webhook": $(get_domain_config webhook),
  "storage": $(get_domain_config storage),
  "ntfy": $(get_domain_config ntfy),
  "gphotos": $(get_domain_config gphotos),
  "speaker": $(get_domain_config speaker)
}
EOF
	exit 0
fi

# POST - Save configuration
if [ "$REQUEST_METHOD" = "POST" ]; then
	# Read POST body (read entire content based on CONTENT_LENGTH)
	if [ -n "$CONTENT_LENGTH" ] && [ "$CONTENT_LENGTH" -gt 0 ]; then
		post_data=$(dd bs=1 count="$CONTENT_LENGTH" 2>/dev/null)
	else
		post_data=""
	fi

	if [ -z "$post_data" ]; then
		send_error "No POST data received"
		exit 1
	fi

	# Save to temp file for processing
	temp_json=$(mktemp)
	echo "$post_data" >"$temp_json"

	# Helper: extract a single top-level key to its own temp file and
	# import that file into the target config.  Keeps domains isolated
	# so a combined payload (e.g. motion+speaker) works correctly.
	import_domain() {
		local domain="$1"
		local target="$2"
		local val
		val=$(jct "$temp_json" get "$domain" 2>/dev/null) || return 1
		local domain_temp
		domain_temp=$(mktemp)
		printf '{"%s": %s}\n' "$domain" "$val" >"$domain_temp"
		jct "$target" import "$domain_temp"
		rm -f "$domain_temp"
	}

	saved=0

	# Motion config — prefer agent when available, else prudynt.json
	if jct "$temp_json" get motion >/dev/null 2>&1; then
		if command -v agentctl >/dev/null 2>&1; then
			enabled=$(jct "$temp_json" get motion.enabled 2>/dev/null | tr -d '"')
			case "$enabled" in
				true | false)
					tmp=$(mktemp /tmp/send2-motion.XXXXXX) || true
					if [ -n "$tmp" ]; then
						printf '{"enabled":%s}\n' "$enabled" >"$tmp"
						agentctl set-setting motion/enabled "$tmp" >/dev/null 2>&1 || true
						rm -f "$tmp"
					fi
					;;
			esac
		fi
		motion_temp=$(mktemp)
		motion_val=$(jct "$temp_json" get motion)
		printf '{"motion": %s}\n' "$motion_val" >"$motion_temp"
		if [ -f "$prudynt_config" ]; then
			jct "$prudynt_config" import "$motion_temp"
			sync
			if pidof prudynt >/dev/null 2>&1; then
				prudyntctl json - <"$motion_temp" >/dev/null 2>&1
			fi
		fi
		rm -f "$motion_temp"
		saved=1
	fi

	# Speaker config - import into send2.json (separate if so it can be
	# combined with motion in a single request)
	if jct "$temp_json" get speaker >/dev/null 2>&1; then
		import_domain speaker "$config_file"
		saved=1
	fi

	if [ "$saved" -eq 1 ]; then
		rm -f "$temp_json"
		send_json_response '{"result":"success","message":"Settings saved"}'
		exit 0
	fi

	# Other domains (still mutually exclusive via elif)
	if jct "$temp_json" get email >/dev/null 2>&1; then
		jct "$config_file" import "$temp_json"

	elif jct "$temp_json" get ftp >/dev/null 2>&1; then
		jct "$config_file" import "$temp_json"

	elif jct "$temp_json" get telegram >/dev/null 2>&1; then
		jct "$config_file" import "$temp_json"

	elif jct "$temp_json" get gotify >/dev/null 2>&1; then
		jct "$config_file" import "$temp_json"

	elif jct "$temp_json" get mqtt >/dev/null 2>&1; then
		jct "$config_file" import "$temp_json"

	elif jct "$temp_json" get webhook >/dev/null 2>&1; then
		jct "$config_file" import "$temp_json"

	elif jct "$temp_json" get storage >/dev/null 2>&1; then
		# Expand variables in storage config
		hostname=$(hostname)
		storage_json=$(jct "$temp_json" get storage)

		# Replace %hostname with actual hostname
		storage_json=$(echo "$storage_json" | sed "s/%hostname/$hostname/g")

		# Write expanded config back to temp file
		echo "{\"storage\":$storage_json}" >"$temp_json"
		jct "$config_file" import "$temp_json"

	elif jct "$temp_json" get ntfy >/dev/null 2>&1; then
		jct "$config_file" import "$temp_json"

	elif jct "$temp_json" get gphotos >/dev/null 2>&1; then
		jct "$config_file" import "$temp_json"

	else
		rm -f "$temp_json"
		send_error "Unknown configuration domain"
		exit 1
	fi

	rm -f "$temp_json"
	send_json_response '{"result":"success","message":"Settings saved"}'
	exit 0
fi

send_error "Invalid request method"
exit 1
