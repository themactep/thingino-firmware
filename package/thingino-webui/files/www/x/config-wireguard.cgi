#!/bin/haserl
<%in _common.cgi %>
<%
[ -f /bin/wg ] || redirect_to "/" "danger" "Your camera does not seem to support WireGuard"

page_title="WireGuard VPN"
params="address allowed dns enabled endpoint keepalive mtu peerpsk peerpub port privkey"
WG_DEV="wg0"

read_from_env "wg"

is_wg_up() {
	ip link show $WG_DEV | grep -q UP
}

wg_status() {
	is_wg_up && echo -n "on" || echo -n "off"
}

if [ "POST" = "$REQUEST_METHOD" ]; then
	tempfile=$(mktemp -u)
	for p in $params; do
		eval echo "wg_$p=\\\"\$POST_wg_$p\\\"" >> $tempfile
	done
	fw_setenv -s $tempfile

	redirect_to $SCRIPT_NAME
fi
%>
<%in _header.cgi %>

<form action="<%= $SCRIPT_NAME %>" method="post" class="mb-4">
<% field_switch "wg_enabled" "Enable WireGuard" %>

<div class="row">
<div class="col col-12 col-lg-6 col-xxl-4 order-2 order-xxl-1">
<h5>Interface</h5>
<% field_password "wg_privkey" "Private Key" %>
<% field_password "wg_peerpsk" "Pre-Shared Key" %>
<% field_text "wg_address" "FQDN or IP address" %>
<% field_text "wg_port" "port" %>
<% field_text "wg_dns" "DNS" %>
</div>
<div class="col col-12 col-lg-6 col-xxl-4 order-3 order-xxl-2">
<h5>Peer</h5>
<% field_text "wg_endpoint" "Endpoint host:port" %>
<% field_text "wg_peerpub" "Peer Public Key" %>
<% field_text "wg_mtu" "MTU" %>
<% field_text "wg_keepalive" "Persistent Keepalive" %>
<% field_text "wg_allowed" "Allowed CIDRs" %>
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
<% button_submit "$wg_action WireGuard" "danger" %>
</form>

<div id="wg-ctrl" class="alert">
<p></p>
<p class="text-end mb-0">
<input type="checkbox" class="btn-check" autocomplete="off" id="btn-wg-control">
<label class="btn" for="btn-wg-control">Switch WireGuard <span></span></label></p>
</div>

<div class="alert alert-dark ui-debug d-none">
<h4 class="mb-3">Debug info</h4>
<% ex "fw_printenv | grep '^wg_' | sed -Ee 's/(key|psk)=.*$/\1=[__redacted__]/' | sort" %>
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

let wgStatus = <% is_wg_up && echo -n 1 || echo -n 0 %>;
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
		" WireGuarg VPN on. Make sure all settings are correct!";
	$('#wg-ctrl label span').textContent = "ON";
}

$('#btn-wg-control').addEventListener('click', ev => {
	var state = ev.target.dataset['state'];
	switchWireGuard(state)
})
</script>

<%in _footer.cgi %>
