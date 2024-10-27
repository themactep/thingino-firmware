#!/bin/haserl
<%in _common.cgi %>
<%
plugin="zerotier"
plugin_name="ZeroTier"
page_title="ZeroTier"
params="enabled nwid"
config_file="$ui_config_dir/$plugin.conf"
service_file=/etc/init.d/S90zerotier
zt_cli_bin=/usr/sbin/zerotier-cli
zt_one_bin=/usr/sbin/zerotier-one

[ -f "$zt_cli_bin" ] || redirect_to "/" "danger" "ZerotierOne client is not a part of your firmware."
[ -f "$zt_one_bin" ] || redirect_to "/" "danger" "$zt_one_bin file not found."
[ -f "$service_file" ] || redirect_to "/" "danger" "$service_file file not found."
[ -f "$config_file" ] || touch $config_file

include $config_file

[ -n "$zerotier_nwid" ] && zt_network_config_file="/var/lib/zerotier-one/networks.d/$zerotier_nwid.conf"

if [ "POST" = "$REQUEST_METHOD" ]; then
	case "$POST_action" in
		create)
			# parse values from parameters
			read_from_post "$plugin" "$params"

			# validate
			if [ "true" = "$zerotier_enabled" ]; then
				[ -z "$zerotier_nwid" ] && set_error_flag "ZeroTier Network ID cannot be empty."
				[ "${#zerotier_nwid}" -ne "16" ] && set_error_flag "ZeroTier Network ID should be 16 digits long."
			fi

			if [ -z "$error" ]; then
				tmp_file=$(mktemp)
				for p in $params; do
					echo "${plugin}_$p=\"$(eval echo \$${plugin}_$p)\"" >>$tmp_file
				done; unset p
				mv $tmp_file $config_file

				update_caminfo
				redirect_back "success" "$plugin_name config updated."
			fi
			;;
		start|open)
			$service_file start >&2
			redirect_back # "success" "Sevice is up"
			;;
		stop|close)
			$service_file stop >&2
			redirect_back # "danger" "Service is down"
			;;
		join)
			$zt_cli_bin join $zerotier_nwid >&2
			while [ -z $(grep nwid "$zt_network_config_file") ]; do sleep 1; done
			redirect_back
			;;
		leave)
			$zt_cli_bin leave $zerotier_nwid >&2
			redirect_back
			;;
		*)
			redirect_back "danger" "Unknown action $POST_action!"
	esac
fi
%>
<%in _header.cgi %>

<div class="row g-4 mb-4">
<div class="col col-lg-4">
<h3>Settings</h3>
<form action="<%= $SCRIPT_NAME %>" method="post">
<% field_hidden "action" "create" %>
<% field_switch "zerotier_enabled" "Enable ZeroTier network on restart" %>
<% field_text "zerotier_nwid" "ZeroTier Network ID" "Don't have it? Get one at <a href=\"https://my.zerotier.com/\">my.zerotier.com</a>" %>
<% button_submit %>
</form>
<br>
<% zerotier-cli info >/dev/null; if [ $? -eq 0 ]; then %>
<div class="alert alert-success">
<h5>ZeroTier Tunnel is open</h5>
<% if [ -f "$zt_network_config_file" ]; then %>
<% zt_id="$(grep ^nwid= $zt_network_config_file | cut -d= -f2)" %>
<% zt_name="$(grep ^n= $zt_network_config_file | cut -d= -f2)" %>
<% if [ -n "$zt_id" ] && [ -n "$zt_name" ]; then %>
<p>Use the following credentials to set up remote access via active virtual tunnel:</p>
<dl>
<dt>NWID: <%= $zt_id %></dd>
<dt>Name: <%= $zt_name %></dd>
</dl>
<form action="<%= $SCRIPT_NAME %>" method="post">
<% field_hidden "action" "leave" %>
<% button_submit "Leave network" "danger" %>
</form>
<% fi %>
<% else %>
<div class="row">
<div class="col">
<form action="<%= $SCRIPT_NAME %>" method="post">
<% field_hidden "action" "join" %>
<% button_submit "Join network" %>
</form>
</div>
<div class="col">
<form action="<%= $SCRIPT_NAME %>" method="post">
<% field_hidden "action" "stop" %>
<% button_submit "Close tunnel" "danger" %>
</form>
</div>
</div>
<% fi %>
</div>
<% else %>
<div class="alert alert-warning">
<h4>ZeroTier Tunnel is closed</h4>
<form action="<%= $SCRIPT_NAME %>" method="post">
<% field_hidden "action" "start" %>
<% button_submit "Open tunnel" %>
</form>
</div>
<% fi %>
</div>

<div class="col col-lg-8">
<h3>Configuration</h3>
<%
[ -f "$service_file" ] && ex "cat $service_file"
[ -f "$config_file" ] && ex "cat $config_file"
[ -f "$zt_network_config_file" ] && ex "cat $zt_network_config_file"
ex "ps | grep zerotier"
%>
</div>
</div>

<%in _footer.cgi %>
