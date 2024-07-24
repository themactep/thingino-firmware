#!/usr/bin/haserl
<%in p/common.cgi %>
<%
plugin="wlan"
page_title="Access to Wi-Fi"
params="ssid pass"

if [ "POST" = "$REQUEST_METHOD" ]; then
	error=""

	# parse values from parameters
	for p in $params; do
		eval ${plugin}_${p}=\$POST_${plugin}_${p}
		sanitize "${plugin}_${p}"
	done; unset p

	# default values
	check_hostname

	[ -z "$wlan_ssid" ] && set_error_flag "WLAN SSID cannot be empty."
	[ -z "$wlan_pass" ] && set_error_flag "WLAN Password cannot be empty."

	if [ -z "$error" ]; then
		fw_setenv wlanssid "$wlan_ssid"

		if [ ${#wlan_pass} -lt 64 ]; then
			tmpfile=$(mktemp)
			wpa_passphrase "$wlan_ssid" "$wlan_pass" > $tmpfile
			wlan_pass=$(grep '^\s*psk=' $tmpfile | cut -d= -f2 | tail -n 1)
		fi
		fw_setenv wlanpass "$wlan_pass"
	fi
fi

# read data from env
wlan_ssid="$(get wlanssid)"
wlan_pass="$(get wlanpass)"
%>
<%in p/header.cgi %>

<form action="<%= $SCRIPT_NAME %>" method="post">
<div class="row g-4 mb-4">
<div class="col-4">
<% field_text "wlan_ssid" "Wireless Network SSID" %>
<% field_text "wlan_pass" "Wireless Network Password" %>
</div>
<div class="col-8">
<% ex "fw_printenv | grep wlan | sort" %>
</div>
</div>
<% button_submit %>
</form>

<%in p/footer.cgi %>
