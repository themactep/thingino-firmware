#!/usr/bin/haserl
<%in p/common.cgi %>
<%
plugin="network"
page_title="Network settings"
params="address dhcp dns_1 dns_2 gateway hostname netmask interface wlan_device wlan_ssid wlan_pass"
tmp_file=/tmp/${plugin}.conf

network_wlan_device="$(get wlandev)"
network_wlan_ssid="$(get wlanssid)"
network_wlan_pass="" # "$(get wlanpass)"

if [ "POST" = "$REQUEST_METHOD" ]; then
	case "$POST_action" in
		changemac)
			if echo "$POST_mac_address" | grep -Eiq '^([0-9a-f]{2}[:-]){5}([0-9a-f]{2})$'; then
				fw_setenv ethaddr $POST_mac_address
				update_caminfo
				redirect_to "reboot.cgi"
			else
				redirect_back "warning" "${POST_mac_address} is as invalid MAC address."
			fi
			;;
		update)
			# parse values from parameters
			for p in $params; do
				eval ${plugin}_${p}=\$POST_${plugin}_${p}
				sanitize "${plugin}_${p}"
			done; unset p

			network_interface=$(echo $network_interfaces | cut -d' ' -f1)

			[ -z "$network_interface" ] && set_error_flag "Default network interface cannot be empty."

			if [ "wlan0" = "$network_interface" ]; then
				[ -z "$network_wlan_device" ] && set_error_flag "WLAN Device cannot be empty."
				[ -z "$network_wlan_ssid" ] && set_error_flag"WLAN SSID cannot be empty."
				[ -z "$network_wlan_pass" ] && set_error_flag "WLAN Password cannot be empty."
			fi

			if [ "false" = "$network_dhcp" ]; then
				network_mode="static"
				[ -z "$network_address" ] && set_error_flag "IP address cannot be empty."
				[ -z "$network_netmask" ] && set_error_flag "Networking mask cannot be empty."
			else
				network_mode="dhcp"
			fi

			if [ -z "$error" ]; then
				command="setnetiface"
				command="${command} -i $network_interface"
				command="${command} -m $network_mode"
				command="${command} -h $network_hostname"

				if [ "wlan0" = "$network_interface" ]; then
					command="${command} -r $network_wlan_device"
					command="${command} -s $network_wlan_ssid"
					command="${command} -p $network_wlan_pass"
				fi

				if [ "dhcp" != "$network_mode" ]; then
					command="${command} -a $network_address"
					command="${command} -n $network_netmask"
					[ -n "$network_gateway" ] && command="${command} -g $network_gateway"
					[ -n "$network_dns_1" ] && command="${command} -d $network_dns_1"
					[ -n "$network_dns_2" ] && command="${command},${network_dns_2}"
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
<%in p/header.cgi %>

<div class="row g-4">
<div class="col col-md-6 col-lg-4 mb-4">
<form action="<%= $SCRIPT_NAME %>" method="post">
<% field_hidden "action" "update" %>
<% field_text "network_hostname" "Hostname" %>
<% field_select "network_interface" "Network interface" "eth0 wlan0" %>
<% field_text "network_wlan_device" "WLAN Device" %>
<% field_text "network_wlan_ssid" "WLAN SSID" %>
<% field_text "network_wlan_pass" "WLAN Password" %>

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
<% ex "cat /etc/hostname" %>
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
		$('#' + id).disabled = c;
		let el = $('#' + id + '_wrap');
		c ? el.classList.add('d-none') : el.classList.remove('d-none');
	});
}

function toggleIface() {
	const ids = ['network_wlan_device','network_wlan_ssid','network_wlan_pass'];
	if ($('#network_interface').value == 'wlan0') {
		ids.forEach(id => $('#' + id + '_wrap').classList.remove('d-none'));
	} else {
		ids.forEach(id => $('#' + id + '_wrap').classList.add('d-none'));
	}
}

$('#network_interface').addEventListener('change', toggleIface);
$('#network_dhcp[type=checkbox]').addEventListener('change', toggleDhcp);

toggleIface();
toggleDhcp();
</script>

<%in p/footer.cgi %>
