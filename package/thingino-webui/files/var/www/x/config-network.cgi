#!/bin/haserl
<%in _common.cgi %>
<%
plugin="network"
page_title="Network settings"

IFACES="eth0 wlan0 usb0"

PARAMS="hostname
eth0_mac_address eth0_enabled eth0_dhcp eth0_address
eth0_netmask eth0_gateway eth0_broadcast eth0_dns1 eth0_dns2
wlan0_mac_address wlan0_enabled wlan0_dhcp wlan0_address
wlan0_netmask wlan0_gateway wlan0_broadcast wlan0_dns1 wlan0_dns2
usb0_mac_address usb0_enabled usb0_dhcp usb0_address
usb0_netmask usb0_gateway usb0_broadcast usb0_dns1 usb0_dns2
"

if [ "POST" = "$REQUEST_METHOD" ]; then
	for p in $PARAMS; do
		eval $p=\$POST_$p
	done

	network_interface=$POST_network_interface
	error_if_empty "$network_interface" "Network interface cannot be empty."

	if [ "false" = "$network_dhcp" ]; then
		network_mode="static"
		error_if_empty "$network_address" "IP address cannot be empty."
		error_if_empty "$network_netmask" "Networking mask cannot be empty."
	else
		network_mode="dhcp"
	fi

	if [ -z "$error" ]; then
		command="setnetiface -i $network_interface -m $network_mode -h \"$(hostname -s)\""
		if [ "dhcp" != "$network_mode" ]; then
			command="$command -a $network_address -n $network_netmask"
			[ -n "$network_gateway" ] && command="$command -g $network_gateway"
			[ -n "$network_dns_1" ] && command="$command -d $network_dns_1"
			[ -n "$network_dns_2" ] && command="$command,$network_dns_2"
		fi
		echo "$command" >>/tmp/webui.log
		eval "$command" >/dev/null 2>&1
		update_caminfo
		redirect_back "success" "Network settings updated."
	fi
fi
%>
<%in _header.cgi %>

<form action="<%= $SCRIPT_NAME %>" method="post" class="mb-4">
<div class="row row-cols-1 row-cols-md-2 row-cols-xl-3">
<div class="col">
<% field_select "network_interface" "Network interface" "$network_interfaces" %>
<% field_switch "network_dhcp" "Use DHCP" %>
</div>
<div class="col">
<% field_text "network_address" "IP Address" %>
<% field_text "network_netmask" "IP Netmask" %>
<% field_text "network_gateway" "Gateway" %>
</div>
<div class="col">
<% field_text "network_dns_1" "DNS 1" %>
<% field_text "network_dns_2" "DNS 2" %>
</div>
</div>
<% field_hidden "action" "update" %>
<% button_submit %>
</form>

<div class="alert alert-dark ui-debug d-none">
<h4 class="mb-3">Debug info</h4>
<% ex "cat /etc/hosts" %>
<% ex "cat /etc/network/interfaces" %>
<% for i in $(ls -1 /etc/network/interfaces.d/); do %>
<% ls /sys/class/net | grep -q $i && ex "cat /etc/network/interfaces.d/$i" %>
<% done %>
<% ex "ip address" %>
<% ex "ip route list" %>
<% [ -f /etc/resolv.conf ] && ex "cat /etc/resolv.conf" %>
</div>

<script>
function toggleDhcp() {
	const c = $('#network_dhcp[type=checkbox]').checked;
	const ids = ['network_address','network_netmask','network_gateway','network_dns_1','network_dns_2'];
	ids.forEach(id => { $(`#${id}`).disabled = c });
}

function toggleIface() {
	const ids = [];
	if ($('#network_interface').value == 'wlan0') {
		ids.forEach(id => $(`#${id}_wrap`).classList.remove('d-none'));
	} else {
		ids.forEach(id => $(`#${id}_wrap`).classList.add('d-none'));
	}
}

$('#network_interface').onchange = toggleIface;
$('#network_dhcp[type=checkbox]').onchange = toggleDhcp;

toggleIface();
toggleDhcp();
</script>

<%in _footer.cgi %>
