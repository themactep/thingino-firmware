#!/bin/haserl
<%in _common.cgi %>
<%
if [ ! -f "/bin/wg" ]; then
	redirect_to "/" "danger" "Your camera does not seem to support WireGuard"
fi

page_title="WireGuard VPN"

WG_DEV="wg0"

defaults() {
	true
}

is_up() {
	ip link show $WG_DEV | grep -q UP
}

status() {
	is_up && echo -n "on" || echo -n "off"
}

read_config() {
	local CONFIG_FILE=/etc/wireguard.json
	[ -f "$CONFIG_FILE" ] || return

	enabled=$(jct $CONFIG_FILE get wireguard.enabled)

	  address=$(jct $CONFIG_FILE get wireguard.address)
	  allowed=$(jct $CONFIG_FILE get wireguard.allowed)
	      dns=$(jct $CONFIG_FILE get wireguard.dns)
	 endpoint=$(jct $CONFIG_FILE get wireguard.endpoint)
	keepalive=$(jct $CONFIG_FILE get wireguard.keepalive)
	      mtu=$(jct $CONFIG_FILE get wireguard.mtu)
	  peerpsk=$(jct $CONFIG_FILE get wireguard.peerpsk)
	  peerhub=$(jct $CONFIG_FILE get wireguard.peerpub)
	     port=$(jct $CONFIG_FILE get wireguard.port)
	  privkey=$(jct $CONFIG_FILE get wireguard.privkey)
}

read_config

if [ "POST" = "$REQUEST_METHOD" ]; then
	error=""

	# Read data from the form
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

		tmpfile="$(mktemp -u).json"
		echo '{}' > $tmpfile
		jct $tmpfile set wireguard.address "$address"
		jct $tmpfile set wireguard.allowed "$allowed"
		jct $tmpfile set wireguard.dns "$dns"
		jct $tmpfile set wireguard.enabled "$enabled"
		jct $tmpfile set wireguard.endpoint "$endpoint"
		jct $tmpfile set wireguard.keepalive "$keepalive"
		jct $tmpfile set wireguard.mtu "$mtu"
		jct $tmpfile set wireguard.peerpsk "$peerpsk"
		jct $tmpfile set wireguard.peerpub "$peerpub"
		jct $tmpfile set wireguard.port "$port"
		jct $tmpfile set wireguard.privkey "$privkey"
		jct /etc/motors.json import $tmpfile
		rm $tmpfile

		redirect_to $SCRIPT_NAME "success" "Data updated."
	else
		redirect_to $SCRIPT_NAME "danger" "Error: $error"
	fi
fi

defaults
%>
<%in _header.cgi %>

<form action="<%= $SCRIPT_NAME %>" method="post" class="mb-4">
<% field_switch "enabled" "Enable WireGuard" %>

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
<p><img src="/a/wireguard.svg" alt="WireGuard" class="img-fluid icon float-start me-2 mb-1">
WireGuard is a fast and simple general purpose VPN.</p>
<p>This interface supports the simple use case of connecting a single tunnel to a peer (server),
and routing traffic from the camera, to a set of CIDRs (networks) through that server.</p>
<% wiki_page "VPN:-Wireguard" %>
</div>
</div>
</div>
<% button_submit %>
</form>

<form action="<%= $SCRIPT_NAME %>" method="post" class="mb-4">
<% field_hidden "action" "startstop" %>
<% button_submit "$action WireGuard" "danger" %>
</form>

<div id="wg-ctrl" class="alert">
<p></p>
<p class="text-end mb-0">
<input type="checkbox" class="btn-check" autocomplete="off" id="btn-wg-control">
<label class="btn" for="btn-wg-control">Switch WireGuard <span></span></label></p>
</div>

<div class="alert alert-dark ui-debug d-none">
<h4 class="mb-3">Debug info</h4>
<% ex "grep '^' $CONFIG_FILE | sed -Ee 's/(key|psk)=.*$/\1=[__redacted__]/' | sort" %>
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
