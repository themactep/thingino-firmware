#!/bin/sh

. /usr/share/common

# Parse query string
parse_query() {
	while IFS='=' read -r key value; do
		value=$(echo "$value" | sed 's/+/ /g; s/%\([0-9A-F][0-9A-F]\)/\\x\1/g' | xargs -0 printf "%b")
		eval "PARAM_$key=\"\$value\""
		export "PARAM_$key"
	done <<-QUERY
	$(echo "$QUERY_STRING" | tr '&' '\n')
	QUERY
}

# URL decode function
urldecode() {
	echo "$1" | sed 's/+/ /g; s/%\([0-9A-F][0-9A-F]\)/\\x\1/g' | xargs -0 printf "%b"
}

# JSON encode string
json_encode() {
	echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\n/\\n/g' | awk '{printf "%s\\n", $0}' | sed '$ s/\\n$//'
}

# Send JSON response
json_response() {
	echo "Content-type: application/json; charset=UTF-8"
	echo "Cache-Control: no-store"
	echo "Pragma: no-cache"
	echo ""
	echo "$1"
}

# Get system info
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

# Parse POST data
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

# Save configuration
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
	temp_file=$(mktemp -u)
	if [ "true" = "$wlanap_enabled" ]; then
		wlanap_pass=$(convert_psk "$wlanap_ssid" "$wlanap_pass")
		printf "wlanap_ssid %s\nwlanap_pass %s\n" \
			"$wlanap_ssid" "$wlanap_pass" > $temp_file
		
		jct /etc/thingino.json set wlan_ap.ssid "$wlanap_ssid"
		jct /etc/thingino.json set wlan_ap.pass "$wlanap_pass"
	else
		wlan_pass=$(convert_psk "$wlan_ssid" "$wlan_pass")
		printf "wlan_ssid %s\nwlan_pass %s\n" \
			"$wlan_ssid" "$wlan_pass" > $temp_file
		
		jct /etc/thingino.json set wlan.ssid "$wlan_ssid"
		jct /etc/thingino.json set wlan.pass "$wlan_pass"
	fi
	fw_setenv -s $temp_file
	rm -f $temp_file
	
	jct /etc/thingino.json set wlan_ap.enabled "$wlanap_enabled"
	
	# Set wlanap status
	conf s wlanap_enabled $wlanap_enabled
	
	# Update env dump
	refresh_env_dump
	
	# Update timezone
	echo "$timezone" > /etc/timezone
	
	# Update root password
	echo "root:$rootpass" | chpasswd -c sha512
	
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

# Main execution
parse_query

case "$PARAM_action" in
	get_info)
		json_response "$(get_info)"
		;;
	save)
		parse_post
		json_response "$(save_config)"
		;;
	*)
		json_response '{"error": "Invalid action"}'
		;;
esac
