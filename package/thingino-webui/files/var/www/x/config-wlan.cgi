#!/bin/haserl
<%in _common.cgi %>
<%
plugin="wlan"
page_title="Wireless Networking"

# ssid, pass
convert_psk() {
	if [ ${#2} -lt 64 ]; then
		local tmpfile=$(mktemp -u)
		wpa_passphrase "$1" "$2" > $tmpfile
		grep '^\s*psk=' $tmpfile | cut -d= -f2 | tail -n 1
	else
		echo "$2"
	fi
}

if [ "POST" = "$REQUEST_METHOD" ]; then
	error=""

	# parse values from parameters
	read_from_post "wlan" "mac pass ssid"
	read_from_post "wlanap" "enabled pass ssid"

	# normalize values
	wlan_mac="${wlan_mac//-/:}"

	# default values for WLAN
	[ -z "$wlan_ssid" ] && set_error_flag "WLAN SSID cannot be empty."
	[ -z "$wlan_pass" ] && set_error_flag "WLAN Password cannot be empty."
	check_mac_address "$wlan_mac" || set_error_flag "Invalid MAC address format."

	# default values for WLAN AP
	if [ "true" = "$wlanap_enabled" ]; then
		[ -z "$wlanap_ssid" ] && set_error_flag "WLAN AP SSID cannot be empty."
		[ -z "$wlanap_pass" ] && set_error_flag "WLAN AP Password cannot be empty."
	fi

	if [ -z "$error" ]; then
		wlan_pass=$(convert_psk "$wlan_ssid" "$wlan_pass")
		wlanap_pass=$(convert_psk "$wlanap_ssid" "$wlanap_pass")

		tmpfile=$(mktemp -u)
		{
			echo "wlanmac=$wlan_mac"
			echo "wlanpass=$wlan_pass"
			echo "wlanssid=$wlan_ssid"
			echo "wlanap_enabled=$wlanap_enabled"
			echo "wlanappass=$wlanap_pass"
			echo "wlanapssid=$wlanap_ssid"
		} > $tmpfile
		fw_setenv -s $tmpfile
	fi
	redirect_to $SCRIPT_NAME
fi

# read data from env
wlan_mac="$(get wlanmac)"
wlan_pass="$(get wlanpass)"
wlan_ssid="$(get wlanssid)"
wlanap_enabled="$(get wlanap_enabled)"
wlanap_pass="$(get wlanappass)"
wlanap_ssid="$(get wlanapssid)"

# defaults
[ -z "$wlanap_ssid" ] && wlanap_ssid="thingino-ap"
%>
<%in _header.cgi %>

<div class="row">
<div class="col">
<ul class="nav nav-underline mb-3" role="tablist">
<li class="nav-item" role="presentation"><a class="nav-link active" aria-current="page" href="#" data-bs-toggle="tab" data-bs-target="#wlan-tab-pane">WLAN</a></li>
<li class="nav-item" role="presentation"><a class="nav-link" href="#" data-bs-toggle="tab" data-bs-target="#wlanap-tab-pane">Wireless AP</a></li>
</ul>

<form action="<%= $SCRIPT_NAME %>" method="post">
<div class="tab-content" id="wireless-tabs">
<div class="tab-pane fade show active" id="wlan-tab-pane" role="tabpanel" aria-labelledby="home-tab" tabindex="0">
<h3 class="mb-3">Wireless Network</h3>
<% field_text "wlan_ssid" "Wireless Network SSID" %>
<% field_text "wlan_pass" "Wireless Network Password" "Plain-text password will be automatically converted to a PSK upon submission" %>
<% field_text "wlan_mac" "Wireless device MAC address" %>
<% button_submit %>
</div>
<div class="tab-pane fade" id="wlanap-tab-pane" role="tabpanel" aria-labelledby="profile-tab" tabindex="1">
<h3 class="mb-3">Wireless Access Point</h3>
<form action="<%= $SCRIPT_NAME %>" method="post">
<% field_switch "wlanap_enabled" "Enable Wireless AP" %>
<% field_text "wlanap_ssid" "Wireless AP SSID" %>
<% field_text "wlanap_pass" "Wireless AP Password" %>
<% button_submit %>
</div>
</div>
</form>

</div>
<div class="col">
<% ex "fw_printenv | grep wlan | sort" %>
<% ex "wlan info" %>
</div>
</div>

<%in _footer.cgi %>
