#!/bin/haserl
<%in _common.cgi %>
<%
# TODO: add an easy way to update NTP servers for static networking.

page_title="Network"

IFACES="eth0 wlan0 usb0"
PARAMS="hostname dns1 dns2"
SUBPARAMS="enabled dhcp ipv6 address mac netmask gateway broadcast"
for i in $IFACES; do
	for p in $SUBPARAMS; do
		PARAMS="$PARAMS ${i}_$p"
	done
done

disable_iface() {
	sed -i "s/^auto /#auto /" /etc/network/interfaces.d/$1
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

iface_ipv6() {
	cat /etc/network/interfaces.d/$1 | grep -q 'dhcp-v6-enabled true' && echo "true"
}

iface_mac() {
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
	ipv6=${7:-false}

	[ -z "$interface" ] && set_error_flag "Network interface is not set"
	[ -z "$mode" ] && set_error_flag "Network mode is not set"
	if [ "static" = "$mode" ]; then
		[ -z "$address" ] && set_error_flag "Interface IP address is not set"
		[ -z "$netmask" ] && set_error_flag "Netmask is not set"
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
		echo -e "\tdhcp-v6-enabled $ipv6"
	} > "/etc/network/interfaces.d/$interface"
	touch /tmp/network-restart.txt
}

setup_wireless_network() {
	local ssid bssid pass psk
	ssid=$1
	bssid=$2
	pass=$3
	psk=$(convert_psk "$ssid" "$pass")

	temp_file=$(mktemp)
	{
		[ -n "$ssid"  ] && echo "wlan_ssid $ssid"
		[ -n "$bssid" ] && echo "wlan_bssid $bssid"
		[ -n "$psk"   ] && echo "wlan_pass $psk"
	} > $temp_file
	fw_setenv -s $temp_file
	rm -f $temp_file
	refresh_env_dump
}

hostname=$(hostname -s)

dns_1=$(grep nameserver /etc/resolv.conf | sed -n 1p | cut -d' ' -f2)
dns_2=$(grep nameserver /etc/resolv.conf | sed -n 2p | cut -d' ' -f2)
if [ -f /etc/default/resolv.conf ]; then
	[ -z "$dns_1" ] && dns_1=$(grep nameserver /etc/default/resolv.conf | sed -n 1p | cut -d' ' -f2)
	[ -z "$dns_2" ] && dns_2=$(grep nameserver /etc/default/resolv.conf | sed -n 2p | cut -d' ' -f2)
fi

eth0_enabled=$(iface_up eth0)
eth0_mac=$(iface_mac eth0)
[ -z "$eth0_mac" ] && eth0_mac="$ethaddr"
is_iface_dhcp eth0 && eth0_dhcp="true"
[ -z "$eth0_address" ] && eth0_address=$(iface_ip_actual eth0)
[ -z "$eth0_address" ] && eth0_address=$(iface_ip_in_etc eth0)
[ -z "$eth0_address" ] && eth0_address="$ipaddr"
eth0_cidr=$(iface_cidr eth0)
eth0_netmask=$(iface_netmask eth0)
eth0_broadcast=$(iface_broadcast eth0)
eth0_gateway=$(iface_gateway eth0)
eth0_ipv6=$(iface_ipv6 eth0)

usb0_enabled=$(iface_up usb0)
usb0_mac=$(iface_mac usb0)
[ -z "$usb0_mac" ] && usb0_mac="$usbmac"
is_iface_dhcp usb0 && usb0_dhcp="true"
[ -z "$usb0_address" ] && usb0_address=$(iface_ip_actual usb0)
[ -z "$usb0_address" ] && usb0_address=$(iface_ip_in_etc usb0)
[ -z "$usb0_address" ] && usb0_address="$usbaddr"
usb0_cidr=$(iface_cidr usb0)
usb0_netmask=$(iface_netmask usb0)
usb0_broadcast=$(iface_broadcast usb0)
usb0_gateway=$(iface_gateway usb0)
usb0_ipv6=$(iface_ipv6 usb0)

wlan0_enabled=$(iface_up wlan0)
wlan0_mac=$(iface_mac wlan0)
[ -z "$wlan0_mac" ] && wlan0_mac="$wlan_mac"
is_iface_dhcp wlan0 && wlan0_dhcp="true"
[ -z "$wlan0_address" ] && wlan0_address=$(iface_ip_actual wlan0)
[ -z "$wlan0_address" ] && wlan0_address=$(iface_ip_in_etc wlan0)
[ -z "$wlan0_address" ] && wlan0_address="$wlan_addr"
wlan0_cidr=$(iface_cidr wlan0)
wlan0_netmask=$(iface_netmask wlan0)
wlan0_broadcast=$(iface_broadcast wlan0)
wlan0_gateway=$(iface_gateway wlan0)
wlan0_ipv6=$(iface_ipv6 wlan0)
# wireless network credentials
wlan0_ssid="$wlan_ssid"
wlan0_bssid="$wlan_bssid"
wlan0_pass="$wlan_pass"

if [ "POST" = "$REQUEST_METHOD" ]; then
	for p in $PARAMS; do
		eval $p=\$POST_$p
	done

	if [ "true" = "$eth0_enabled" ]; then
		if [ "false" = "$eth0_dhcp" ]; then
			eth0_mode="static"
			check_mac_address "$eth0_mac" || set_error_flag "eth0 MAC address format is invalid."
			error_if_empty "$eth0_address" "eth0 IP address cannot be empty."
			error_if_empty "$eth0_netmask" "eth0 networking mask cannot be empty."
		else
			eth0_mode="dhcp"
		fi
	fi

	if [ "true" = "$wlan0_enabled" ]; then
		if [ "false" = "$wlan0_dhcp" ]; then
			wlan0_mode="static"

			# normalize values
			wlan0_mac="${wlan0_mac//-/:}"
			wlan0_bssid="${wlan0_bssid//-/:}"
			check_mac_address "$wlan0_mac" || \
				set_error_flag "wlan0 MAC address format is invalid."
			if [ -n "$wlan_bssid" ]; then
				check_mac_address "$wlan0_bssid" || \
					set_error_flag "wlan0 BSSID format is invalid."
			fi
			error_if_empty "$wlan0_address" "wlan0 IP address cannot be empty."
			error_if_empty "$wlan0_netmask" "wlan0 networking mask cannot be empty."
		else
			wlan0_mode="dhcp"
		fi
	fi

	if [ "true" = "$usb0_enabled" ]; then
		if [ "false" = "$usb0_dhcp" ]; then
			usb0_mode="static"
			check_mac_address "$usb0_mac" || \
				set_error_flag "usb0 MAC address format is invalid."
			error_if_empty "$usb0_address" "usb0 IP address cannot be empty."
			error_if_empty "$usb0_netmask" "usb0 networking mask cannot be empty."
		else
			usb0_mode="dhcp"
		fi
	fi

	# validate hostname as per RFC952, RFC1123
	[ -z "$POST_hostname" ] && \
		set_error_flag "Hostname cannot be empty"
	echo "$POST_hostname" | grep ' ' && \
		set_error_flag "Hostname cannot contain whitespaces"
	bad_chars=$(echo "$POST_hostname" | sed 's/[0-9A-Z\.-]//ig')
	[ -z "$bad_chars" ] || \
		set_error_flag "Only alphanumeric characters, hyphen and period are allowed, not $bad_chars"

	# validate dns servers
	dns_1=$POST_dns_1
	dns_2=$POST_dns_2
	[ -z "$dns_1" ] && dns_1=$dns_2
	[ -z "$dns_1" ] && set_error_flag "At least one DNS server required"

	# read data from POST
	wlan0_ssid="$POST_wlan0_ssid"
	wlan0_pass="$POST_wlan0_pass"
	wlan0_bssid="$POST_wlan0_bssid"

	# set WLAN AP status
	wlanap_ssid="$POST_wlanap_ssid"
	wlanap_pass="$POST_wlanap_pass"
	conf s wlanap_enabled $POST_wlanap_enabled

	# validate wireless network credentials if not empty
	if [ "true" = "$wlan0_enabled" ] && [ -n "$wlan0_ssid$wlan0_pass" ]; then
		[ -z "$wlan0_ssid" ] && \
			set_error_flag "wlan0 SSID cannot be empty"
		[ -z "$wlan0_pass" ] && \
			set_error_flag "wlan0 password cannot be empty"
		[ ${#wlan0_pass} -lt 8 ] && \
			set_error_flag "wlan0 password cannot be shorter than 8 characters."
	fi

	if [ -z "$error" ]; then
		setup_iface eth0 "$eth0_mode" "$eth0_address" "$eth0_netmask" "$eth0_gateway" "$eth0_broadcast"
		fw_setenv ethaddr "$eth0_mac"
		[ "true" = "$eth0_enabled" ] || disable_iface eth0

		setup_iface wlan0 "$wlan0_mode" "$wlan0_address" "$wlan0_netmask" "$wlan0_gateway" "$wlan0_broadcast"
		fw_setenv wlan_mac "$wlan0_mac"
		[ "true" = "$wlan0_enabled" ] || disable_iface wlan0

		setup_iface usb0 "$usb0_mode" "$usb0_address" "$usb0_netmask" "$usb0_gateway" "$usb0_broadcast"
		fw_setenv usbmac "$usb0_mac"
		[ "true" = "$usb0_enabled" ] || disable_iface usb0

		refresh_env_dump

		hostname=$POST_hostname
		[ "$hostname" = "$(hostname_in_etc)" ] || \
			echo "$hostname" > /etc/hostname
		[ "$hostname" = "$(hostname_in_hosts)" ] || \
			sed -i "/^127.0.1.1/c127.0.1.1\t$hostname" /etc/hosts
		hostname "$hostname"

		[ -z "$dns_1$dns_2" ] || \
			setup_dns "$dns_1" "$dns_2"

		# update wireless network credentials if not empty
		[ "true" = "$wlan0_enabled" ] && [ -n "$wlan0_ssid$wlan0_pass" ] && \
			setup_wireless_network "$wlan0_ssid" "$wlan0_bssid" "$wlan0_pass"

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

<nav class="navbar navbar-expand p-1">
<ul class="navbar-nav nav-underline" role="tablist">
<li class="nav-item"><a href="#" data-bs-toggle="tab" id="tab1" data-bs-target="#tab1-pane" class="nav-link active">Wi-Fi Network</a></li>
<li class="nav-item"><a href="#" data-bs-toggle="tab" id="tab2" data-bs-target="#tab2-pane" class="nav-link">Wi-Fi AP</a></li>
</ul>
</nav>
<div class="tab-content" id="wlan-tabs">
<div class="tab-pane fade show active" id="tab1-pane" role="tabpanel" aria-labelledby="tab1">
<div class="row g-1">
<% field_text "wlan0_ssid" "Wireless Network Name (SSID)" %>
<% field_text "wlan0_bssid" "Access Point MAC Address (BSSID)" "Only if SSID broadcast is enabled!" %>
<% field_text "wlan0_pass" "Wi-Fi Network Password" "$STR_PASSWORD_TO_PSK" "" "$STR_EIGHT_OR_MORE_CHARS" %>
</div>
</div>
<div class="tab-pane fade" id="tab2-pane" role="tabpanel" aria-labelledby="tab2">
<% field_text "wlanap_ssid" "Wi-Fi AP SSID" %>
<% field_text "wlanap_pass" "Wi-Fi AP Password" "$STR_PASSWORD_TO_PSK" "" "$STR_EIGHT_OR_MORE_CHARS" %>
<% field_switch "wlanap_enabled" "Enable Wi-Fi AP" %>
</div>
</div>
</div>

<% for i in $IFACES; do %>
<div class="col">
<div class="card <%= $i %>">
<div class="card-header"><% field_switch "${i}_enabled" "${i} enabled" %></div>
<div class="card-body">

<div class="input-group mb-3">
<input type="text" id="<%= $i %>_mac" name="<%= $i %>_mac" class="form-control" value="<% eval echo \$${i}_mac %>">
<button class="btn btn-secondary generate-mac-address" type="button" data-iface="<%= $i %>" title="Generate MAC address"><img src="/a/generate.svg" alt="" class="img-fluid"></button>
</div>

<% field_switch "${i}_dhcp" "Use DHCP" %>
<div class="static">
<% field_text "${i}_address" "IP Address" %>
<% field_text "${i}_netmask" "Netmask" %>
<% field_text "${i}_gateway" "Gateway" %>
<% field_text "${i}_broadcast" "Broadcast" %>
</div>
<% field_switch "${i}_ipv6" "Use IPv6 (DHCPv6)" %>
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
	const input = $('#' + iface + '_mac');
	if (input.value != "") {
		alert("There's a value in MAC address field. Please empty the field and try again.");
	} else {
		input.value = generateMacAddress(iface);
	}
}));
</script>

<div class="alert alert-dark ui-debug d-none">
<h4 class="mb-3">Debug info</h4>
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
<% ex "grep wlan $ENV_DUMP_FILE" %>
</div>

<%in _footer.cgi %>
