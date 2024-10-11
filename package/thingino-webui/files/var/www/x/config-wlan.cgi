#!/bin/haserl
<%in _common.cgi %>
<%
plugin="wlan"
page_title="Access to Wi-Fi"
params="ssid pass mac"

if [ "POST" = "$REQUEST_METHOD" ]; then
	error=""

	# parse values from parameters
	for p in $params; do
		eval ${plugin}_$p=\$POST_${plugin}_$p
		sanitize "${plugin}_$p"
	done; unset p

	# normalize values
	wlan_mac="${wlan_mac//-/:}"

	# default values
	[ -z "$wlan_ssid" ] && set_error_flag "WLAN SSID cannot be empty."
	[ -z "$wlan_pass" ] && set_error_flag "WLAN Password cannot be empty."
	check_mac_address "$wlan_mac" || set_error_flag "Invalid MAC address format."

	if [ -z "$error" ]; then
		[ "$(get wlanssid)" = "$wlan_ssid" ] || fw_setenv wlanssid "$wlan_ssid"

		if [ ${#wlan_pass} -lt 64 ]; then
			tmpfile=$(mktemp)
			wpa_passphrase "$wlan_ssid" "$wlan_pass" > $tmpfile
			wlan_pass=$(grep '^\s*psk=' $tmpfile | cut -d= -f2 | tail -n 1)
		fi
		[ "$(get wlanpass)" = "$wlan_pass" ] || fw_setenv wlanpass "$wlan_pass"

		if [ -z "$wlan_mac" ] && [ "$(get wlanmac)" != "$wlan_mac" ]; then
			fw_setenv wlanmac "$wlan_mac"
		fi
	fi
	redirect_to $SCRIPT_NAME
fi

# read data from env
wlan_ssid="$(get wlanssid)"
wlan_pass="$(get wlanpass)"
wlan_mac="$(get wlanmac)"
%>
<%in _header.cgi %>

<form action="<%= $SCRIPT_NAME %>" method="post">
<div class="row g-4 mb-4">
<div class="col">
<% field_text "wlan_ssid" "Wireless Network SSID" %>
<% field_text "wlan_pass" "Wireless Network Password" "Plain-text password will be automatically converted to a PSK upon submission" %>
<% field_text "wlan_mac" "Wireless device MAC address" %>
</div>
<div class="col">
<% ex "fw_printenv | grep wlan | sort" %>
</div>
</div>
<% button_submit %>
</form>

<%in _footer.cgi %>
