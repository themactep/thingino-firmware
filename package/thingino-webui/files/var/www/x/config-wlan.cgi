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

	# validate values for WLAN
	check_mac_address "$wlan_mac" || set_error_flag "Invalid MAC address format."
	[ -z "$wlan_ssid" ] && set_error_flag "WLAN SSID cannot be empty."
	[ -z "$wlan_pass" ] && set_error_flag "WLAN Password cannot be empty."
	[ ${#wlan_pass} -lt 8 ] && set_error_flag "WLAN Password cannot be shorter than 8 characters."

	# validate values for WLAN AP
	if [ "true" = "$wlanap_enabled" ]; then
		[ -z "$wlanap_ssid" ] && set_error_flag "WLAN AP SSID cannot be empty."
		[ -z "$wlanap_pass" ] && set_error_flag "WLAN AP Password cannot be empty."
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
			echo "wlanap_enabled=$wlanap_enabled"
			echo "wlanap_pass=$wlanap_pass"
			echo "wlanap_ssid=$wlanap_ssid"
		} > $tmpfile
		fw_setenv -s $tmpfile
	fi
	redirect_to $SCRIPT_NAME
fi

# read data from env
wlan_mac="$(get wlanmac)"
wlan_pass="$(get wlanpass)"
wlan_ssid="$(get wlanssid)"
read_from_env "wlanap"

# defaults
[ -z "$wlanap_ssid" ] && wlanap_ssid="thingino-ap"
%>
<%in _header.cgi %>

<div class="row">
<div class="col">
<ul class="nav nav-underline mb-3" role="tablist" id="tabs">
<li class="nav-item" role="presentation"><button type="button" role="tab" class="nav-link" data-bs-toggle="tab" data-bs-target="#wlan-tab-pane" id="wlan-tab">Wi-Fi Network</button></li>
<li class="nav-item" role="presentation"><button type="button" role="tab" class="nav-link" data-bs-toggle="tab" data-bs-target="#wlanap-tab-pane" id="wlanap-tab">Wi-Fi Access Point</button></li>
</ul>
<form action="<%= $SCRIPT_NAME %>" method="post">
<div class="tab-content" id="wireless-tabs">
<div class="tab-pane fade" id="wlan-tab-pane" role="tabpanel" aria-labelledby="home-tab" tabindex="0">
<% field_text "wlan_ssid" "Wi-Fi Network SSID" %>
<% field_text "wlan_pass" "Wi-Fi Network Password" "Plain-text password will be automatically converted to a PSK upon submission" "" "$STR_EIGHT_OR_MORE_CHARS" %>
<% field_text "wlan_mac" "Wi-Fi device MAC address" %>
</div>
<div class="tab-pane fade" id="wlanap-tab-pane" role="tabpanel" aria-labelledby="profile-tab" tabindex="1">
<% field_switch "wlanap_enabled" "Enable Wi-Fi AP" %>
<% field_text "wlanap_ssid" "Wi-Fi AP SSID" %>
<% field_text "wlanap_pass" "Wi-Fi AP Password" "" "" "$STR_EIGHT_OR_MORE_CHARS" %>
</div>
</div>
<% button_submit %>
</form>
</div>
<div class="col">
<% ex "fw_printenv | grep wlan | sort" %>
<% ex "wlan info" %>
</div>
</div>

<script>
$$('#tabs button').forEach(el => {
  const trigger = new bootstrap.Tab(el)
  el.addEventListener('click', ev => {
    ev.preventDefault()
    trigger.show()
  })
})
bootstrap.Tab.getInstance($('#wlanap_enabled').checked ? $('#wlanap-tab') : $('#wlan-tab')).show()
</script>

<%in _footer.cgi %>
