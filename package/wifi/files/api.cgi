#!/bin/sh

. /usr/share/common

parse_query() {
	while IFS='=' read -r key value; do
		value=$(printf '%b' "$(echo "$value" | sed 's/+/ /g; s/%\([0-9A-Fa-f][0-9A-Fa-f]\)/\\x\1/g')")
		eval "PARAM_$key=\"\$value\""
		export "PARAM_$key"
	done <<-QUERY
	$(echo "$QUERY_STRING" | tr '&' '\n')
	QUERY
}

urldecode() {
	printf '%b' "$(echo "$1" | sed 's/+/ /g; s/%\([0-9A-Fa-f][0-9A-Fa-f]\)/\\x\1/g')"
}

json_encode() {
	echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\n/\\n/g' | awk '{printf "%s\\n", $0}' | sed '$ s/\\n$//'
}

json_response() {
	echo "Content-type: application/json; charset=UTF-8"
	echo "Cache-Control: no-store"
	echo "Pragma: no-cache"
	echo ""
	echo "$1"
}

get_info() {
	hostname=$(hostname)
	image_id=$(awk -F= '/IMAGE_ID/{print $2}' $OS_RELEASE_FILE)
	build_id=$(awk -F= '/BUILD_ID/{print $2}' $OS_RELEASE_FILE | tr -d '"')
	wlan_mac=$(ip link show wlan0 2>/dev/null | awk '/ether/ {print $2}')

	cat <<-EOF
	{
		"hostname": "$(json_encode "$hostname")",
		"image_id": "$(json_encode "$image_id")",
		"build_id": "$(json_encode "$build_id")",
		"wlan_mac": "$(json_encode "$wlan_mac")"
	}
	EOF
}

scan_networks() {
	# Check if wpa_cli is available
	if ! command -v wpa_cli >/dev/null 2>&1; then
		echo '{"error": "wpa_cli not available"}'
		return
	fi

	# Check if scan is already in progress
	SCAN_LOCK="/tmp/wpa_scan.lock"
	SCAN_WAIT=0
	SHOULD_SCAN=1

	# Wait up to 8 seconds for ongoing scan to complete
	while [ -f "$SCAN_LOCK" ] && [ $SCAN_WAIT -lt 8 ]; do
		# Check if lock is stale (older than 15 seconds)
		LOCK_AGE=$(( $(date +%s) - $(stat -c %Y "$SCAN_LOCK" 2>/dev/null || echo 0) ))
		if [ $LOCK_AGE -gt 15 ]; then
			rm -f "$SCAN_LOCK"
			break
		fi
		sleep 1
		SCAN_WAIT=$((SCAN_WAIT + 1))
	done

	# If still locked after waiting, use cached results
	if [ -f "$SCAN_LOCK" ]; then
		SHOULD_SCAN=0
	else
		# Create lock file and trigger new scan
		touch "$SCAN_LOCK"
		wpa_cli -i wlan0 scan >/dev/null 2>&1
		sleep 2
	fi

	# Get scan results and format as JSON
	echo "{\"networks\": ["

	first=1
	wpa_cli -i wlan0 scan_results 2>/dev/null | tail -n +2 | while IFS=$'\t' read -r bssid freq signal flags ssid; do
		# Skip empty SSIDs and header
		[ -z "$ssid" ] || [ "$ssid" = "ssid" ] && continue

		# Determine security type
		if echo "$flags" | grep -q "WPA2-PSK"; then
			security="WPA2"
		elif echo "$flags" | grep -q "WPA-PSK"; then
			security="WPA"
		elif echo "$flags" | grep -q "WEP"; then
			security="WEP"
		else
			security="Open"
		fi

		# Output JSON without trailing commas
		if [ $first -eq 0 ]; then
			echo ","
		else
			first=0
		fi
		cat <<-NETWORK
		{
			"ssid": "$(json_encode "$ssid")",
			"bssid": "$(json_encode "$bssid")",
			"signal": $signal,
			"security": "$(json_encode "$security")"
		}
		NETWORK
	done

	echo "]}"

	# Clean up lock if we created it
	[ $SHOULD_SCAN -eq 1 ] && rm -f "$SCAN_LOCK"
}

parse_post() {
	if [ "$REQUEST_METHOD" = "POST" ]; then
		if [ -n "$CONTENT_LENGTH" ]; then
			read -n "$CONTENT_LENGTH" POST_DATA
		else
			read POST_DATA
		fi

		while IFS='=' read -r key value; do
			value=$(urldecode "$value")
			eval "PARAM_$key=\"\$value\""
			export "PARAM_$key"
		done <<-POST
		$(echo "$POST_DATA" | tr '&' '\n')
		POST
	fi
}

save_config() {
	hostname="$PARAM_hostname"
	rootpass="$PARAM_rootpass"
	rootpkey="$PARAM_rootpkey"
	timezone="$PARAM_timezone"
	wlanap_enabled="$PARAM_wlanap_enabled"
	wlanap_pass="$PARAM_wlanap_pass"
	wlanap_ssid="$PARAM_wlanap_ssid"
	wlan_pass="$PARAM_wlan_pass"
	wlan_ssid="$PARAM_wlan_ssid"

	# Trim trailing whitespaces from submitted values
	hostname=$(echo "$hostname" | sed 's/[[:space:]]*$//')
	rootpass=$(echo "$rootpass" | sed 's/[[:space:]]*$//')
	rootpkey=$(echo "$rootpkey" | sed 's/[[:space:]]*$//')
	timezone=$(echo "$timezone" | sed 's/[[:space:]]*$//')
	wlanap_pass=$(echo "$wlanap_pass" | sed 's/[[:space:]]*$//')
	wlanap_ssid=$(echo "$wlanap_ssid" | sed 's/[[:space:]]*$//')
	wlan_pass=$(echo "$wlan_pass" | sed 's/[[:space:]]*$//')
	wlan_ssid=$(echo "$wlan_ssid" | sed 's/[[:space:]]*$//')

	# FIXME: Sanitize ssid and password

	# Validate hostname
	bad_chars=$(echo "$hostname" | sed 's/[0-9A-Z\.-]//ig')
	if [ -n "$bad_chars" ]; then
		cat <<-EOF
		{
			"success": false,
			"error": "Hostname cannot contain $bad_chars"
		}
		EOF
		return
	fi

	# Update hostname
	hostname "$hostname"
	echo "$hostname" > /etc/hostname

	# Update wlan settings
	if [ "true" = "$wlanap_enabled" ]; then
		temp_file=$(mktemp -u)
		echo '{}' > $temp_file
		wlanap_pass=$(convert_psk "$wlanap_ssid" "$wlanap_pass")
		jct $temp_file set wlan_ap.ssid "$wlanap_ssid"
		jct $temp_file set wlan_ap.pass "$wlanap_pass"
		jct $temp_file set wlan_ap.enabled "$wlanap_enabled"
		jct /etc/thingino.json import $temp_file
		rm -f $temp_file
	else
		log="/tmp/wpa.log"
		echo "# created on $(date +%c)
ctrl_interface=/run/wpa_supplicant
update_config=1
ap_scan=1

network={
        ssid=\"$wlan_ssid\"
        psk=\"$wlan_pass\"
	bgscan=\"simple:30:-70:3600\"
}
" > /etc/wpa_supplicant.conf
	fi

	# Update timezone
	echo "$timezone" > /etc/timezone

	# Update root password
	printf '%s:%s\n' "root" "$rootpass" | chpasswd -c sha512

	# Update SSH key if provided
	if [ -n "$rootpkey" ]; then
		echo "$rootpkey" | tr -d '\r' | sed 's/^ //g' > /root/.ssh/authorized_keys
	fi

	# Update interface for onvif
	jct /etc/onvif.json set ifs wlan0

	# Success response
	cat <<-EOF
	{
		"success": true
	}
	EOF

	# Reboot in background
	reboot -d 2 &
}

parse_query

case "$PARAM_action" in
	get_info)
		json_response "$(get_info)"
		;;
	scan_networks)
		json_response "$(scan_networks)"
		;;
	save)
		parse_post
		json_response "$(save_config)"
		;;
	*)
		json_response '{"error": "Invalid action"}'
		;;
esac
