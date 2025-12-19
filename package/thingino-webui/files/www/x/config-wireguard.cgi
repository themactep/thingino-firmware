#!/bin/haserl
<%in _common.cgi %>
<%
if [ ! -f "/bin/wg" ]; then
	redirect_to "/" "danger" "Your camera does not seem to support WireGuard"
fi

page_title="WireGuard VPN"

domain="wireguard"
config_file="/etc/thingino.json"
temp_config_file="/tmp/$domain.json"

WG_DEV="wg0"

is_up() {
	ip link show $WG_DEV | grep -q UP
}

status() {
	is_up && echo -n "on" || echo -n "off"
}

defaults() {
	true
}

save_config() {
	[ -f "$temp_config_file" ] || echo '{}' > "$temp_config_file"
	jct "$temp_config_file" set "$domain.$1" "$2" >/dev/null 2>&1
}

get_value() {
	jct $config_file get "$domain.$1"
}

read_config() {
	[ -f "$config_file" ] || return

	enabled=$(get_value "enabled")
	address=$(get_value "address")
	allowed=$(get_value "allowed")
	dns=$(get_value "dns")
	endpoint=$(get_value "endpoint")
	keepalive=$(get_value "keepalive")
	mtu=$(get_value "mtu")
	peerpsk=$(get_value "peerpsk")
	peerhub=$(get_value "peerpub")
	port=$(get_value "port")
	privkey=$(get_value "privkey")
}

read_config

if [ "POST" = "$REQUEST_METHOD" ]; then
	error=""

	address="$POST_address"
	allowed="$POST_allowed"
	dns="$POST_dns"
	enabled="$POST_enabled"
	endpoint="$POST_endpoint"
	keepalive="$POST_keepalive"
	mtu="$POST_mtu"
	peerpsk="$POST_peerpsk"
	peerpub="$POST_peerpub"
	port="$POST_port"
	privkey="$POST_privkey"

	defaults

	if [ -z "$error" ]; then
		save_config "address" "$address"
		save_config "allowed" "$allowed"
		save_config "dns" "$dns"
		save_config "enabled" "$enabled"
		save_config "endpoint" "$endpoint"
		save_config "keepalive" "$keepalive"
		save_config "mtu" "$mtu"
		save_config "peerpsk" "$peerpsk"
		save_config "peerpub" "$peerpub"
		save_config "port" "$port"
		save_config "privkey" "$privkey"

		jct "$config_file" import "$temp_config_file"
		rm "$temp_config_file"

		redirect_to $SCRIPT_NAME "success" "Data updated."
	else
		redirect_to $SCRIPT_NAME "danger" "Error: $error"
	fi
fi

defaults
%>
<%in _header.cgi %>

<form action="<%= $SCRIPT_NAME %>" method="post" class="mb-4">
<div class="row">
<div class="col col-12 col-lg-6 col-xxl-4 order-2 order-xxl-1">
<h5>Interface</h5>
<% field_password "privkey" "Private Key" %>
<% field_password "peerpsk" "Pre-Shared Key" %>
<% field_text "address" "FQDN or IP address" %>
<% field_text "port" "port" %>
<% field_text "dns" "DNS" %>
</div>
<div class="col col-12 col-lg-6 col-xxl-4 order-3 order-xxl-2">
<h5>Peer</h5>
<% field_text "endpoint" "Endpoint host:port" %>
<% field_text "peerpub" "Peer Public Key" %>
<% field_text "mtu" "MTU" %>
<% field_text "keepalive" "Persistent Keepalive" %>
<% field_text "allowed" "Allowed CIDRs" %>
</div>
<div class="col col-12 col-lg-12 col-xxl-4 order-1 order-xxl-3">
<div class="alert alert-info">
<p><img src="/a/wireguard.svg" alt="WireGuard" class="img-fluid icon float-start me-3 mb-1"> WireGuard is a fast and simple general purpose VPN.</p>
<p>This interface supports the simple use case of connecting a single tunnel to a peer (server), and routing traffic from the camera, to a set of CIDRs (networks) through that server.</p>
<% wiki_page "VPN:-Wireguard" %>
</div>

<div id="wg-ctrl" class="alert">
<p id="button_placeholder"></p>
<p class="text-end mb-0">
<input type="checkbox" class="btn-check" autocomplete="off" id="btn-wg-control">
<label class="btn" for="btn-wg-control">Switch WireGuard <span id="status_placeholder"></span></label></p>
</div>

</div>
</div>

<% field_switch "enabled" "Run WireGuard at boot" %>

<% button_submit %>
</form>

<div class="alert alert-dark ui-debug d-none">
<h4 class="mb-3">Debug info</h4>
<% ex "jct $config_file get $domain | sed -Ee 's/(key|psk)=.*$/\1=[__redacted__]/'" %>
<% ex "wg show $WG_DEV 2>&1 | grep -A5 endpoint" %>
</div>

<script>
async function switchWireGuard(state) {
	await fetch("/x/json-wireguard.cgi?iface=<%= $WG_DEV %>&amp;s=" + state)
		.then(response => response.json())
		.then(data => {
			$('#btn-wg-control').checked = (data.message.status == 1);
		});
}

let wgStatus = <% is_up && echo -n 1 || echo -n 0 %>;
if (wgStatus == 1) {
	$('#wg-ctrl').classList.add("alert-danger");
	$('#wg-ctrl .btn').classList.add("btn-danger");
	$('#wg-ctrl p:first-child').textContent = "Attention! Switching WireGuard off" +
		" while working over the VPN connection will render this camera inaccessible!" +
		" Make sure you have a backup plan.";
	$('#wg-ctrl label span').textContent = "OFF";
} else {
	$('#wg-ctrl').classList.add("alert-success");
	$('#wg-ctrl .btn').classList.add("btn-success");
	$('#wg-ctrl p:first-child').textContent = "Please click the button below to switch" +
		" WireGuard VPN on. Make sure all settings are correct!";
	$('#wg-ctrl label span').textContent = "ON";
}

$('#btn-wg-control').addEventListener('click', ev => {
	var state = ev.target.dataset['state'];
	switchWireGuard(state)
})
</script>

<%in _footer.cgi %>
