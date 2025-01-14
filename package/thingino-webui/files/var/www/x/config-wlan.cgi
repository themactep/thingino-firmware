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

	read_from_post "wlan" "bssid mac pass ssid"
	read_from_post "wlanap" "enabled pass ssid"

	# normalize values
	wlan_mac="${wlan_mac//-/:}"
	wlan_bssid="${wlan_bssid//-/:}"

	# validate values for WLAN
	check_mac_address "$wlan_mac" || set_error_flag "Invalid MAC address format."
	if [ -n "$wlan_bssid" ]; then
		check_mac_address "$wlan_bssid" || set_error_flag "Invalid WLAN BSSID format."
	fi

	error_if_empty "$wlan_ssid" "WLAN SSID cannot be empty."
	error_if_empty "$wlan_pass" "WLAN Password cannot be empty."
	[ ${#wlan_pass} -lt 8 ] && set_error_flag "WLAN Password cannot be shorter than 8 characters."

	# validate values for WLAN AP
	if [ "true" = "$wlanap_enabled" ]; then
		error_if_empty "$wlanap_ssid" "WLAN AP SSID cannot be empty."
		error_if_empty "$wlanap_pass" "WLAN AP Password cannot be empty."
		[ ${#wlanap_pass} -lt 8 ] && set_error_flag "WLAN AP Password cannot be shorter than 8 characters."
	fi

	if [ -z "$error" ]; then
		wlan_pass=$(convert_psk "$wlan_ssid" "$wlan_pass")
		wlanap_pass=$(convert_psk "$wlanap_ssid" "$wlanap_pass")

		tmpfile=$(mktemp -u)
		{
			echo "wlanmac=$wlan_mac"
			echo "wlanpass=$wlan_pass"
			echo "wlanssid=$wlan_ssid"
			echo "wlanbssid=$wlan_bssid"
			echo "wlanap_enabled=$wlanap_enabled"
			echo "wlanap_pass=$wlanap_pass"
			echo "wlanap_ssid=$wlanap_ssid"
		} > $tmpfile
		fw_setenv -s $tmpfile
	fi
	redirect_to $SCRIPT_NAME
fi

# read data from env
wlan_mac="$(fw_printenv -n wlanmac)"
wlan_pass="$(fw_printenv -n wlanpass)"
wlan_ssid="$(fw_printenv -n wlanssid)"
wlan_bssid="$(fw_printenv -n wlanbssid)"
read_from_env "wlanap"

# defaults
default_for wlanap_ssid "thingino-ap"
%>
<%in _header.cgi %>

<nav class="navbar navbar-expand-lg mb-4 p-1">
<button class="navbar-toggler" type="button" data-bs-toggle="collapse" data-bs-target="#nbWifi"
 aria-controls="nbStreamer" aria-label="Toggle navigation"><span class="navbar-toggler-icon"></span></button>
<div class="collapse navbar-collapse" id="nbWifi">
<ul class="navbar-nav nav-underline" role="tablist">
<li class="nav-item"><a href="#" data-bs-toggle="tab" id="tab1" data-bs-target="#tab1-pane" class="nav-link active">Wi-Fi Network</a></li>
<li class="nav-item"><a href="#" data-bs-toggle="tab" id="tab2" data-bs-target="#tab2-pane" class="nav-link">Wi-Fi Access Point</a></li>
</ul>
</div>
</nav>

<div class="row row-cols-1 row-cols-lg-2">
<div class="col">

<form action="<%= $SCRIPT_NAME %>" method="post" class="mb-4">
<div class="tab-content" id="wlan-tabs">
<div class="tab-pane fade show active" id="tab1-pane" role="tabpanel" aria-labelledby="tab1">
<div class="row g-1">
<div class="col"><% field_text "wlan_ssid" "Wireless Network Name (SSID)" %></div>
<div class="col"><% field_text "wlan_bssid" "Access Point MAC Address (BSSID)" %></div>
</div>
<% field_text "wlan_pass" "Wi-Fi Network Password" "$STR_PASSWORD_TO_PSK" "" "$STR_EIGHT_OR_MORE_CHARS" %>
<% field_text "wlan_mac" "Wi-Fi device MAC address" %>
</div>
<div class="tab-pane fade" id="tab2-pane" role="tabpanel" aria-labelledby="tab2">
<% field_text "wlanap_ssid" "Wi-Fi AP SSID" %>
<% field_text "wlanap_pass" "Wi-Fi AP Password" "$STR_PASSWORD_TO_PSK" "" "$STR_EIGHT_OR_MORE_CHARS" %>
<% field_switch "wlanap_enabled" "Enable Wi-Fi AP" %>
</div>
</div>
<% button_submit %>
</form>

</div>
</div>

<div class="alert alert-dark ui-debug d-none">
<h4 class="mb-3">Debug info</h4>
<% ex "fw_printenv | grep wlan | sort" %>
<% is_ap && ex "wlan cli sta_info | tr ' ' '\n'" || ex "wlan info" %>
</div>

<script>
$$('#nbWifi a').forEach(el => {
	const trigger = new bootstrap.Tab(el)
	el.addEventListener('click', ev => {
		ev.preventDefault()
		trigger.show()
	})
})
bootstrap.Tab.getInstance($('#wlanap_enabled').checked ? $('#tab2') : $('#tab1')).show()
</script>

<%in _footer.cgi %>
