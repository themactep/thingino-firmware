#!/bin/haserl
<%in _common.cgi %>
<%
plugin="wireguard"
page_title="WireGuard"

[ -f /bin/wg ] || redirect_to "/" "danger" "Your camera does not seem to support WireGuard"

read_from_env "wg"

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

<form action="<%= $SCRIPT_NAME %>" method="post" class="mb-4">
<% field_switch "wg_enabled" "Enable WireGuard" %>

<div class="row row-cols-1 row-cols-md-2 row-cols-xl-3">
<div class="col">
<div class="alert alert-info">
<p>WireGuard is a fast and simple general purpose VPN.</p>
<% wiki_page "WireGuard-VPN" %>
</div>
</div>
<div class="col">
<h5>Interface</h5>
<% field_hidden "action" "wgconfig" %>
<% field_password "wg_privkey" "Private Key" %>
<% field_password "wg_peerpsk" "Pre-Shared Key" %>
<% field_text "wg_address" "Address" %>
<% field_text "wg_port" "Listen Port" %>
<% field_text "wg_dns" "DNS" %>
</div>
<div class="col">
<h5>Peer</h5>
<% field_text "wg_endpoint" "Endpoint host:port" %>
<% field_text "wg_peerpub" "Peer Public Key" %>
<% field_text "wg_mtu" "MTU" %>
<% field_text "wg_keepalive" "Persistent Keepalive" %>
<% field_text "wg_allowed" "Allowed CIDRs" %>
</div>
</div>
<% button_submit %>
</form>

<form action="<%= $SCRIPT_NAME %>" method="post" class="mb-4">
<% field_hidden "action" "startstop" %>
<% button_submit "$wg_action WireGuard" "danger" %>
</form>

<div class="alert alert-dark ui-debug">
<h4 class="mb-3">Debug info</h4>
<% ex "fw_printenv | grep '^wg_' | sed -Ee 's/(key|psk)=.*$/\1=[__redacted__]/' | sort" %>
<% ex "wg show $WG_DEV 2>&1 | grep -A 5 endpoint" %>
</div>

<%in _footer.cgi %>
