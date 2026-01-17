#!/bin/sh

. /usr/share/common

parse_query() {
	while IFS='=' read -r key value; do
		value=$(echo "$value" | sed 's/+/ /g; s/%\([0-9A-F][0-9A-F]\)/\\x\1/g' | xargs -0 printf "%b")
		eval "PARAM_$key=\"\$value\""
		export "PARAM_$key"
	done <<-QUERY
	$(echo "$QUERY_STRING" | tr '&' '\n')
	QUERY
}

urldecode() {
	echo "$1" | sed 's/+/ /g; s/%\([0-9A-F][0-9A-F]\)/\\x\1/g' | xargs -0 printf "%b"
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
	temp_file=$(mktemp -u)
	echo '{}' > $temp_file
	if [ "true" = "$wlanap_enabled" ]; then
		wlanap_pass=$(convert_psk "$wlanap_ssid" "$wlanap_pass")
		jct $temp_file set wlan_ap.ssid "$wlanap_ssid"
		jct $temp_file set wlan_ap.pass "$wlanap_pass"
	else
		wlan_pass=$(convert_psk "$wlan_ssid" "$wlan_pass")
		jct $temp_file set wlan.ssid "$wlan_ssid"
		jct $temp_file set wlan.pass "$wlan_pass"
	fi
	jct $temp_file set wlan_ap.enabled "$wlanap_enabled"
	jct /etc/thingino.json import $temp_file
	rm -f $temp_file

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
