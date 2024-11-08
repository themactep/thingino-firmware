#!/bin/haserl
<%in _common.cgi %>
<%
plugin="network"
page_title="Network settings"
params="address dhcp dns_1 dns_2 gateway netmask interface"

if [ "POST" = "$REQUEST_METHOD" ]; then
	case "$POST_action" in
		changemac)
			if echo "$POST_mac_address" | grep -Eiq '^([0-9a-f]{2}[:-]){5}([0-9a-f]{2})$'; then
				fw_setenv ethaddr $POST_mac_address
				update_caminfo
				redirect_to "reboot.cgi"
			else
				redirect_back "warning" "$POST_mac_address is as invalid MAC address."
			fi
			;;
		update)
			# parse values from parameters
			read_from_post "$plugin" "$params"

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
			;;
	esac
fi
%>
<%in _header.cgi %>

<div class="row g-4">
<div class="col col-md-6 col-lg-4 mb-4">
<form action="<%= $SCRIPT_NAME %>" method="post">
<% field_hidden "action" "update" %>
<% field_select "network_interface" "Network interface" "$network_interfaces" %>
<% field_switch "network_dhcp" "Use DHCP" %>
<% field_text "network_address" "IP Address" %>
<% field_text "network_netmask" "IP Netmask" %>
<% field_text "network_gateway" "Gateway" %>
<% field_text "network_dns_1" "DNS 1" %>
<% field_text "network_dns_2" "DNS 2" %>
<% button_submit %>
</form>
</div>
<div class="col col-md-6 col-lg-8">
<% ex "cat /etc/hosts" %>
<% ex "cat /etc/network/interfaces" %>
<% for i in $(ls -1 /etc/network/interfaces.d/); do %>
<% ls /sys/class/net | grep -q $i && ex "cat /etc/network/interfaces.d/$i" %>
<% done %>
<% ex "ip address" %>
<% ex "ip route list" %>
<% [ -f /etc/resolv.conf ] && ex "cat /etc/resolv.conf" %>
</div>
</div>

<script>
function toggleDhcp() {
	const c = $('#network_dhcp[type=checkbox]').checked;
	const ids = ['network_address','network_netmask','network_gateway','network_dns_1','network_dns_2'];
	ids.forEach(id => {
		$(`#${id}`).disabled = c;
		let el = $(`#${id}_wrap`);
		c ? el.classList.add('d-none') : el.classList.remove('d-none');
	});
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
