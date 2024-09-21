#!/bin/haserl
<%in _common.cgi %>
<%
plugin="wireguard"
page_title="WireGuard"

[ -f /bin/wg ] || redirect_to "/" "danger" "Your camera does not seem to support WireGuard"

wg_address=$(get wg_address)
wg_allowed=$(get wg_allowed)
wg_dns=$(get wg_dns)
wg_enabled=$(get wg_enabled)
wg_endpoint=$(get wg_endpoint)
wg_keepalive=$(get wg_keepalive)
wg_mtu=$(get wg_mtu)
wg_peerpsk=$(get wg_peerpsk)
wg_peerpub=$(get wg_peerpub)
wg_port=$(get wg_port)
wg_privkey=$(get wg_privkey)

WG_DEV="wg0"
WG_CTL="/etc/init.d/S42wireguard"

if ip link show $WG_DEV 2>&1 | grep -q 'UP' ; then
	wg_state="up"
	wg_action="Stop"
else
	wg_state="down"
	wg_action="Start"
fi

if [ "POST" = "$REQUEST_METHOD" ]; then
	if [ "startstop" = "$POST_action" ] ; then
		if [ $wg_state = "down" ] ; then
			$WG_CTL force
		else
			$WG_CTL stop
		fi
	fi
	if [ "wgconfig" = "$POST_action" ] ; then
	 	rm -f /tmp/wg_env_*
		wg_env_script=$(mktemp wg_env_XXXXXX)
		for k in address allowed dns enabled endpoint keepalive mtu peerpsk peerpub port privkey; do
			eval echo wg_$k \$POST_wg_$k >> $wg_env_script
		done
		fw_setenv -s $wg_env_script
	fi
	redirect_to $SCRIPT_NAME
fi
%>

<%in _header.cgi %>

<div class="row row-cols-1 row-cols-md-2 row-cols-lg-3 g-4 mb-4">
	<div class="col">
		<form action="<%= $SCRIPT_NAME %>" method="post">
		<h3>Interface Settings</h3>
		<% field_hidden "action" "wgconfig" %>
		<% field_password "wg_privkey" "Private Key" %>
		<% field_password "wg_peerpsk" "Pre-Shared Key" %>
		<% field_text "wg_address" "Address" %>
		<% field_text "wg_port" "Listen Port" %>
		<% field_text "wg_dns" "DNS" %>
		<% field_switch "wg_enabled" "Enable WireGuard" %>
	</div>
	<div class="col">
		<h3>Peer Settings</h3>
		<% field_text "wg_endpoint" "Endpoint host:port" %>
		<% field_text "wg_peerpub" "Peer Public Key" %>
		<% field_text "wg_mtu" "MTU" %>
		<% field_text "wg_keepalive" "Persistent Keepalive" %>
		<% field_text "wg_allowed" "Allowed CIDRs" %>
		<% button_submit %>
		</form>
	</div>
	<div class="col">
		<h3>Environment Settings</h3>
		<% ex "fw_printenv | grep '^wg_' | sed -Ee 's/(key|psk)=.*$/\1=[__redacted__]/' | sort" %>
		<% ex "wg show $WG_DEV 2>&1 | grep -A 5 endpoint" %>
		<form action="<%= $SCRIPT_NAME %>" method="post">
		<% field_hidden "action" "startstop" %>
		<% button_submit "$wg_action WireGuard" "danger" %>
		</form>
	</div>
</div>

<%in _footer.cgi %>
