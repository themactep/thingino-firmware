#!/bin/haserl
<%in _common.cgi %>
<%
plugin="network"
page_title="Network settings"

IFACES="eth0 wlan0 usb0"
PARAMS="hostname dns1 dns2"
SUBPARAMS="enabled dhcp address macaddr netmask gateway broadcast"
for i in $IFACES; do
	for p in $SUBPARAMS; do
		PARAMS="$PARAMS ${i}_$p"
	done
done

hostname_in_env() {
	fw_printenv -n hostname
}

hostname_in_etc() {
	cat /etc/hostname
}

hostname_in_hosts() {
	sed -nE "s/^127.0.1.1\t(.*)$/\1/p" /etc/hosts
}

hostname_in_release() {
	echo $HOSTNAME
}

iface_up() {
	local endpoint="/sys/class/net/$1/operstate"
	[ -f $endpoint ] && [ "up" = "$(cat $endpoint)" ] && echo "true"
}

hostname=$(hostname -s)
dns_1=$(grep nameserver /etc/resolv.conf | sed -n 1p | cut -d' ' -f2)
dns_2=$(grep nameserver /etc/resolv.conf | sed -n 2p | cut -d' ' -f2)

eth0_enabled=$(iface_up eth0)
eth0_macaddr=$(cat /sys/class/net/eth0/address)
if cat /etc/network/interfaces.d/eth0 | grep '^iface' | grep -q 'dhcp'; then
	eth0_dhcp="true"
else
	eth0_address=$(ip r | sed -nE "/eth0/s/.+src ([0-9\.]+).+?/\1/p" | uniq)
	eth0_cidr=$(ip r | sed -nE "/eth0/s/^[0-9\.]+(\/[0-9]+).+?/\1/p")
	eth0_netmask=$(ifconfig eth0 | grep "Mask:" | cut -d: -f4) # FIXME: Maybe convert from $network_cidr?
	eth0_broadcast=$(ifconfig eth0 | sed -En "s/.*Bcast:([0-9\.]+).*/\1/p")
	eth0_gateway=$(ip r | grep eth0 | awk '/via/{print $3}')
fi

wlan0_enabled=$(iface_up wlan0)
wlan0_macaddr=$(cat /sys/class/net/wlan0/address)
if cat /etc/network/interfaces.d/wlan0 | grep '^iface' | grep -q 'dhcp'; then
	wlan0_dhcp="true"
else
	wlan0_address=$(ip r | sed -nE "/wlan0/s/.+src ([0-9\.]+).+?/\1/p" | uniq)
	wlan0_cidr=$(ip r | sed -nE "/wlan0/s/^[0-9\.]+(\/[0-9]+).+?/\1/p")
	wlan0_netmask=$(ifconfig wlan0 | grep "Mask:" | cut -d: -f4) # FIXME: Maybe convert from $network_cidr?
	wlan0_broadcast=$(ifconfig wlan0 | sed -En "s/.*Bcast:([0-9\.]+).*/\1/p")
	wlan0_gateway=$(ip r | grep wlan0 | awk '/via/{print $3}')
fi

usb0_enabled=$(iface_up usb0)
usb0_macaddr=$(cat /sys/class/net/usb0/address)
if cat /etc/network/interfaces.d/usb0 | grep '^iface' | grep -q 'dhcp'; then
	usb0_dhcp="true"
else
	usb0_address=$(ip r | sed -nE "/usb0/s/.+src ([0-9\.]+).+?/\1/p" | uniq)
	usb0_cidr=$(ip r | sed -nE "/usb0/s/^[0-9\.]+(\/[0-9]+).+?/\1/p")
	usb0_netmask=$(ifconfig usb0 | grep "Mask:" | cut -d: -f4) # FIXME: Maybe convert from $network_cidr?
	usb0_broadcast=$(ifconfig usb0 | sed -En "s/.*Bcast:([0-9\.]+).*/\1/p")
	usb0_gateway=$(ip r | grep usb0 | awk '/via/{print $3}')
fi

if [ "POST" = "$REQUEST_METHOD" ]; then
	for p in $PARAMS; do
		eval $p=\$POST_$p
	done

#	network_interface=$POST_network_interface
#	error_if_empty "$network_interface" "Network interface cannot be empty."

	if [ "true" = "$eth0_enabled" ]; then
		if [ "false" = "$eth0_dhcp" ]; then
			eth0_mode="static"
			error_if_empty "$eth0_address" "IP address cannot be empty."
			error_if_empty "$eth0_netmask" "Networking mask cannot be empty."
		else
			eth0_mode="dhcp"
		fi
	fi

	if [ "true" = "$wlan0_enabled" ]; then
		if [ "false" = "$wlan0_dhcp" ]; then
			wlan0_mode="static"
			error_if_empty "$wlan0_address" "IP address cannot be empty."
			error_if_empty "$wlan0_netmask" "Networking mask cannot be empty."
		else
			wlan0_mode="dhcp"
		fi
	fi

	if [ "true" = "$usb0_enabled" ]; then
		if [ "false" = "$usb0_dhcp" ]; then
			usb0_mode="static"
			error_if_empty "$usb0_address" "IP address cannot be empty."
			error_if_empty "$usb0_netmask" "Networking mask cannot be empty."
		else
			usb0_mode="dhcp"
		fi
	fi

	[ -z "$POST_hostname" ] && set_error_flag "Hostname cannot be empty"

	# validate hostname as per RFC952, RFC1123
	echo "$POST_hostname" | grep ' ' && set_error_flag "Hostname cannot contain whitespaces"
	bad_chars=$(echo "$POST_hostname" | sed 's/[0-9A-Z\.-]//ig')
	[ -z "$bad_chars" ] || set_error_flag "Hostname only allowed to contain alphabetic characters, numeric characters, hyphen and period. Please get rid of this: ${bad_chars}"

	if [ -z "$error" ]; then
		if [ "true" = "$eth0_enabled" ]; then
			command="setnetiface -i eth0 -m $eth0_mode -h \"$(hostname -s)\""
			if [ "dhcp" != "$eth0_mode" ]; then
				command="$command -a $eth0_address -n $eth0_netmask"
				[ -n "$eth0_gateway" ] && command="$command -g $eth0_gateway"
				[ -n "$eth0_dns_1" ] && command="$command -d $eth0_dns_1"
				[ -n "$eth0_dns_2" ] && command="$command,$eth0_dns_2"
			fi
			echo "$command" >>/tmp/webui.log
			eval "$command" >/dev/null 2>&1
		else
			sed -i 's/^auto /#auto /' /etc/network/interfaces.d/eth0
		fi

		if [ "true" = "$wlan0_enabled" ]; then
			command="setnetiface -i wlan0 -m $wlan0_mode -h \"$(hostname -s)\""
			if [ "dhcp" != "$wlan0_mode" ]; then
				command="$command -a $wlan0_address -n $wlan0_netmask"
				[ -n "$wlan0_gateway" ] && command="$command -g $wlan0_gateway"
				[ -n "$wlan0_dns_1" ] && command="$command -d $wlan0_dns_1"
				[ -n "$wlan0_dns_2" ] && command="$command,$wlan0_dns_2"
			fi
			echo "$command" >>/tmp/webui.log
			eval "$command" >/dev/null 2>&1
		else
			sed -i 's/^auto /#auto /' /etc/network/interfaces.d/wlan0
		fi

		if [ "true" = "$usb0_enabled" ]; then
			command="setnetiface -i usb0 -m $usb0_mode -h \"$(hostname -s)\""
			if [ "dhcp" != "$usb0_mode" ]; then
				command="$command -a $usb0_address -n $usb0_netmask"
				[ -n "$usb0_gateway" ] && command="$command -g $usb0_gateway"
				[ -n "$usb0_dns_1" ] && command="$command -d $usb0_dns_1"
				[ -n "$usb0_dns_2" ] && command="$command,$usb0_dns_2"
			fi
			echo "$command" >>/tmp/webui.log
			eval "$command" >/dev/null 2>&1
		else
			sed -i 's/^auto /#auto /' /etc/network/interfaces.d/usb0
		fi

		hostname=$POST_hostname
		[ "$hostname" = "$(hostname_in_env)" ] || fw_setenv hostname "$hostname"
		[ "$hostname" = "$(hostname_in_etc)" ] || echo "$hostname" > /etc/hostname
		[ "$hostname" = "$(hostname_in_hosts)" ] || sed -i "/^127.0.1.1/s/\t.*$/\t$hostname/" /etc/hosts
		[ "$hostname" = "$(hostname_in_release)" ] || sed -i "/^HOSTNAME/s/=.*$/=$hostname/" /etc/os-release
		hostname "$hostname"

		update_caminfo
		redirect_back "success" "Network settings updated."
	fi
fi
%>
<%in _header.cgi %>

<form action="<%= $SCRIPT_NAME %>" method="post" class="mb-4">
<div class="row row-cols-1 row-cols-md-2 row-cols-xxl-4">
<div class="col">
<% field_text "hostname" "Hostname" %>
<% field_text "dns_1" "DNS 1" %>
<% field_text "dns_2" "DNS 2" %>
</div>
<% for i in $IFACES; do %>
<div class="col">
<div class="card">
<div class="card-header"><% field_switch "${i}_enabled" "${i} enabled" %></div>
<div class="card-body">
<% field_text "${i}_macaddr" "MAC Address" %>
<% field_switch "${i}_dhcp" "Use DHCP" %>
<% field_text "${i}_address" "IP Address" %>
<% field_text "${i}_netmask" "Netmask" %>
<% field_text "${i}_gateway" "Gateway" %>
<% field_text "${i}_broadcast" "Broadcast" %>
</div>
</div>
</div>
<% done %>
</div>

<% field_hidden "action" "update" %>
<% button_submit %>
</form>

<div class="alert alert-dark ui-debug d-none">
<h4 class="mb-3">Debug info</h4>
<% ex "fw_printenv -n hostname" %>
<% ex "hostname" %>
<% ex "cat /etc/hostname" %>
<% ex "echo \$HOSTNAME" %>
<% ex "grep 127.0.1.1 /etc/hosts" %>
<% ex "cat /etc/hosts" %>
<% ex "cat /etc/resolv.conf" %>
<% ex "cat /etc/network/interfaces" %>
<% for i in $(ls -1 /etc/network/interfaces.d/); do %>
<% ex "cat /etc/network/interfaces.d/$i" %>
<%# ls /sys/class/net | grep -q $i && ex "cat /etc/network/interfaces.d/$i" %>
<% done %>
<% ex "ifconfig" %>
<% ex "ip address" %>
<% ex "ip route list" %>
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
