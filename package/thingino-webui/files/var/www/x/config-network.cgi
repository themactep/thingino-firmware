#!/bin/haserl
<%in _common.cgi %>
<%
page_title="Network"

IFACES="eth0 wlan0 usb0"
PARAMS="hostname dns1 dns2"
SUBPARAMS="enabled dhcp address macaddr netmask gateway broadcast"
for i in $IFACES; do
	for p in $SUBPARAMS; do
		PARAMS="$PARAMS ${i}_$p"
	done
done

disable_iface() {
	sed -i "s/^auto /#auto /" /etc/network/interfaces.d/$1
}

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

iface_broadcast() {
	[ -d /sys/class/net/$1 ] || return
	ifconfig $1 | sed -En "s/.*Bcast:([0-9\.]+).*/\1/p"
}

iface_cidr() {
	ip r | sed -nE "/$1/s/^[0-9\.]+(\/[0-9]+).+?/\1/p"
}

iface_gateway() {
	ip r | grep $1 | awk '/via/{print $3}'
}

iface_ip_actual() {
	ip r | sed -nE "/$1/s/.+src ([0-9\.]+).+?/\1/p" | uniq
}

iface_ip_in_etc() {
	cat /etc/network/interfaces.d/$1 | sed -nE "s/.*address ([0-9\.]+).*/\1/p"
}

iface_macaddr() {
	[ -f /sys/class/net/$1/address ] || return
	cat /sys/class/net/$1/address
}

iface_netmask() {
	 # FIXME: Maybe convert from $network_cidr?
	[ -d /sys/class/net/$1 ] || return
	ifconfig $1 | grep "Mask:" | cut -d: -f4
}

iface_up() {
	local endpoint="/sys/class/net/$1/carrier"
	[ -f $endpoint ] && [ "$(cat $endpoint)" -eq 1 ] && echo "true"
}

is_iface_dhcp() {
	cat /etc/network/interfaces.d/$1 | grep '^iface' | grep -q 'dhcp'
}

setup_dns() {
	[ -d "/etc/default" ] || mkdir -p /etc/default
	local ip
	{
		echo "# set from web ui"
		for ip in $1 $2; do
			echo "nameserver $ip"
		done
	} > /etc/default/resolv.conf
}

setup_iface() {
	local interface mode address netmask gateway broadcast
	interface=$1
	mode=${2:-dhcp}
	address=$3
	netmask=$4
	gateway=$5
	broadcast=$6

	[ -z "$interface" ] && set_error_flag "Network interface is not set"
        [ -z "$mode" ] && set_error_flag "Network mode is not set"
	if [ "static" = "$mode" ]; then
		[ -z "$address" ] && die "Interface IP address is not set"
		[ -z "$netmask" ] && die "Netmask is not set"
	fi

	{
		echo -e "auto $interface"
		echo -e "iface $interface inet $mode"
		if [ "static" = "$mode" ]; then
			echo -e "\taddress $address"
			echo -e "\tnetmask $netmask"
			[ -n "$gateway" ] && echo -e "\tgateway $gateway"
			[ -n "$broadcast" ] && echo -e "\tbroadcast $broadcast"
		fi
		echo -e "\tdhcp-v6-enabled true"
	} > "/etc/network/interfaces.d/$interface"
	touch /tmp/network-restart.txt
}

setup_wireless_network() {
	local ssid password
	ssid=$1
	password=$2

	temp_env=$(mktemp)
	{
		[ -n "$ssid" ] && echo "wlanssid $ssid"
		[ -n "$password" ] && echo "wlanpass $password"
	} > "$temp_env"
	fw_setenv -s "$temp_env"
	rm "$temp_env"
}

hostname=$(hostname -s)

dns_1=$(grep nameserver /etc/resolv.conf | sed -n 1p | cut -d' ' -f2)
dns_2=$(grep nameserver /etc/resolv.conf | sed -n 2p | cut -d' ' -f2)
if [ -f /etc/default/resolv.conf ]; then
	[ -z "$dns_1" ] && dns_1=$(grep nameserver /etc/default/resolv.conf | sed -n 1p | cut -d' ' -f2)
	[ -z "$dns_2" ] && dns_2=$(grep nameserver /etc/default/resolv.conf | sed -n 2p | cut -d' ' -f2)
fi

eth0_enabled=$(iface_up eth0)
eth0_macaddr=$(iface_macaddr eth0)
[ -z "$eth0_macaddr" ] && eth0_macaddr=$(fw_printenv -n ethaddr)
is_iface_dhcp eth0 && eth0_dhcp="true"
eth0_address=$(iface_ip_in_etc eth0)
[ -z "$eth0_address" ] && eth0_address=$(fw_printenv -n ipaddr)
[ -z "$eth0_address" ] && eth0_address=$(iface_ip_actual eth0)
eth0_cidr=$(iface_cidr eth0)
eth0_netmask=$(iface_netmask eth0)
eth0_broadcast=$(iface_broadcast eth0)
eth0_gateway=$(iface_gateway eth0)

wlan0_enabled=$(iface_up wlan0)
wlan0_macaddr=$(iface_macaddr wlan0)
[ -z "$wlan0_macaddr" ] && wlan0_macaddr=$(fw_printenv -n wlanmac)
is_iface_dhcp wlan0 && wlan0_dhcp="true"
wlan0_address=$(iface_ip_in_etc wlan0)
[ -z "$wlan0_address" ] && wlan0_address=$(fw_printenv -n wlanaddr)
[ -z "$wlan0_address" ] && wlan0_address=$(iface_ip_actual wlan0)
wlan0_cidr=$(iface_cidr wlan0)
wlan0_netmask=$(iface_netmask wlan0)
wlan0_broadcast=$(iface_broadcast wlan0)
wlan0_gateway=$(iface_gateway wlan0)

usb0_enabled=$(iface_up usb0)
usb0_macaddr=$(iface_macaddr usb0)
is_iface_dhcp usb0 && usb0_dhcp="true"
usb0_address=$(iface_ip_in_etc usb0)
[ -z "$usb0_address" ] && usb0_address=$(fw_printenv -n usbaddr)
[ -z "$usb0_address" ] && usb0_address=$(iface_ip_actual usb0)
usb0_cidr=$(iface_cidr usb0)
usb0_netmask=$(iface_netmask usb0)
usb0_broadcast=$(iface_broadcast usb0)
usb0_gateway=$(iface_gateway usb0)

if [ "POST" = "$REQUEST_METHOD" ]; then
	for p in $PARAMS; do
		eval $p=\$POST_$p
	done

	if [ "true" = "$eth0_enabled" ]; then
		if [ "false" = "$eth0_dhcp" ]; then
			eth0_mode="static"
			error_if_empty "$eth0_address" "eth0 IP address cannot be empty."
			error_if_empty "$eth0_netmask" "eth0 networking mask cannot be empty."
		else
			eth0_mode="dhcp"
		fi
	fi

	if [ "true" = "$wlan0_enabled" ]; then
		if [ "false" = "$wlan0_dhcp" ]; then
			wlan0_mode="static"
			error_if_empty "$wlan0_address" "wlan0 IP address cannot be empty."
			error_if_empty "$wlan0_netmask" "wlan0 networking mask cannot be empty."
		else
			wlan0_mode="dhcp"
		fi
	fi

	if [ "true" = "$usb0_enabled" ]; then
		if [ "false" = "$usb0_dhcp" ]; then
			usb0_mode="static"
			error_if_empty "$usb0_address" "usb0 IP address cannot be empty."
			error_if_empty "$usb0_netmask" "usb0 networking mask cannot be empty."
		else
			usb0_mode="dhcp"
		fi
	fi

	# validate hostname as per RFC952, RFC1123
	[ -z "$POST_hostname" ] && set_error_flag "Hostname cannot be empty"
	echo "$POST_hostname" | grep ' ' && set_error_flag "Hostname cannot contain whitespaces"
	bad_chars=$(echo "$POST_hostname" | sed 's/[0-9A-Z\.-]//ig')
	[ -z "$bad_chars" ] || set_error_flag "Only alphanumeric characters, hyphen and period are allowed. Please get rid of this: $bad_chars"

	# validate dns servers
	dns_1=$POST_dns_1
	dns_2=$POST_dns_2
	[ -z "$dns_1" ] && dns_1=$dns_2
	[ -z "$dns_1" ] && set_error_flag "At least one DNS server required"

	# validate wireless network credentials if not empty
	if [ "true" = "$wlan0_enabled" ] && [ -n "$POST_wlan0_ssid$POST_wlan0_password" ]; then
		[ -z "$POST_wlan0_ssid" ] && set_error_flag "WLAN SSID cannot be empty"
		[ -z "$POST_wlan0_password" ] && set_error_flag "WLAN password cannot be empty"
	fi

	if [ -z "$error" ]; then
		setup_iface eth0 "$eth0_mode" "$eth0_address" "$eth0_netmask" "$eth0_gateway" "$eth0_broadcast"
		[ "true" = "$eth0_enabled" ] || disable_iface eth0

		setup_iface wlan0 "$wlan0_mode" "$wlan0_address" "$wlan0_netmask" "$wlan0_gateway" "$wlan0_broadcast"
		[ "true" = "$wlan0_enabled" ] || disable_iface wlan0

		setup_iface usb0 "$usb0_mode" "$usb0_address" "$usb0_netmask" "$usb0_gateway" "$usb0_broadcast"
		[ "true" = "$usb0_enabled" ] || disable_iface usb0

		hostname=$POST_hostname
		[ "$hostname" = "$(hostname_in_env)" ] || fw_setenv hostname "$hostname"
		[ "$hostname" = "$(hostname_in_etc)" ] || echo "$hostname" > /etc/hostname
		[ "$hostname" = "$(hostname_in_hosts)" ] || sed -i "/^127.0.1.1/s/\t.*$/\t$hostname/" /etc/hosts
		[ "$hostname" = "$(hostname_in_release)" ] || sed -i "/^HOSTNAME/s/=.*$/=$hostname/" /etc/os-release
		hostname "$hostname"

		[ -z "$dns_1$dns_2" ] || setup_dns "$dns_1" "$dns_2"

		# update wireless network credentials if not empty
		[ "true" = "$wlan0_enabled" ] && [ -n "$POST_wlan0_ssid$POST_wlan0_password" ] && \
			setup_wireless_network "$POST_wlan0_ssid" "$POST_wlan0_password"

		update_caminfo
		redirect_back "success" "Network settings updated."
	fi
fi
%>
<%in _header.cgi %>

<form action="<%= $SCRIPT_NAME %>" method="post" class="mb-4">
<div class="row row-cols-1 row-cols-md-2 row-cols-xxl-4 g-3">
<div class="col">
<% field_text "hostname" "Hostname" %>
<% field_text "dns_1" "DNS 1" %>
<% field_text "dns_2" "DNS 2" %>
</div>
<% for i in $IFACES; do %>
<div class="col">
<div class="card <%= $i %>">
<div class="card-header"><% field_switch "${i}_enabled" "${i} enabled" %></div>
<div class="card-body">

<div class="input-group mb-3">
<input type="text" id="<%= $i %>_macaddr" name="<%= $i %>_macaddr" class="form-control" value="<% eval echo \$${i}_macaddr %>">
<button class="btn btn-secondary generate-mac-address" type="button" data-iface="<%= $i %>" title="Generate MAC address"><img src="/a/generate.svg" alt="" class="img-fluid"></button>
</div>

<% field_switch "${i}_dhcp" "Use DHCP" %>
<div class="static">
<% field_text "${i}_address" "IP Address" %>
<% field_text "${i}_netmask" "Netmask" %>
<% field_text "${i}_gateway" "Gateway" %>
<% field_text "${i}_broadcast" "Broadcast" %>
</div>
<% if [ "wlan0" = "$i" ]; then %>
<% field_text "wlan0_ssid" "SSID" %>
<% field_text "wlan0_password" "Password" %>
<% fi %>
</div>
</div>
</div>
<% done %>
</div>

<% field_hidden "action" "update" %>
<% button_submit %>
</form>

<script>
function toggleDhcp(iface) {
	const c = $('#' + iface + '_dhcp[type=checkbox]').checked;
	const ids = [
		iface + '_address',
		iface + '_netmask',
		iface + '_gateway',
		iface + '_broadcast',
	];
	ids.forEach(id => { $('#' + id).disabled = c });
}

function toggleIface(iface) {
	const ids = [];
	if ($('#' + iface + '_enabled[type=checkbox]').checked) {
		$('.' + iface + ' .card-body').style.visibility = 'visible';
	} else {
		$('.' + iface + ' .card-body').style.visibility = 'hidden';
	}
}

function generateMacAddress(iface) {
	let mac = "";
	for (let i = 1; i <= 6; i++) {
		let b = ((Math.random() * 255) >>> 0);
		if (i === 1) {
			b = b | 2;
			b = b & ~1;
		}
		mac += b.toString(16).toUpperCase().padStart(2, '0');
		if (i < 6) mac += ":";
	}
	return mac;
}

[ 'eth0', 'wlan0', 'usb0' ].forEach(iface => {
	$('#' + iface + '_dhcp').addEventListener('change', ev => toggleDhcp(iface));
	$('#' + iface + '_enabled').addEventListener('change', ev => toggleIface(iface));
	toggleDhcp(iface);
	toggleIface(iface);
});

$$('.generate-mac-address').forEach(el => el.addEventListener('click', ev => {
	ev.preventDefault();
	const iface = ev.target.dataset.iface;
	const input = $('#' + iface + '_macaddr');
	if (input.value != "") {
		alert("There's a value in MAC address field. Please empty the field and try again.");
	} else {
		input.value = generateMacAddress(iface);
	}
}));
</script>

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
<% ex "fw_printenv -n wlandev" %>
<% ex "fw_printenv -n wlanssid" %>
<% ex "fw_printenv -n wlanpass" %>
</div>

<%in _footer.cgi %>
