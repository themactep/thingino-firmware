#!/bin/haserl
<%in _common.cgi %>
<%
page_title="ZeroTier"
params="enabled nwid"

domain="zerotier"
config_file="/etc/zerotier.json"
temp_config_file="/tmp/$domain.json"

ZT_CLI_BIN=/usr/sbin/zerotier-cli
ZT_ONE_BIN=/usr/sbin/zerotier-one

get_value() {
        jct "$config_file" get "$domain.$1" 2>/dev/null
}

set_value() {
        [ -f "$temp_config_file" ] || echo '{}' > "$temp_config_file"
        jct "$temp_config_file" set "$domain.$1" "$2" >/dev/null 2>&1
}

read_config() {
        [ -f "$config_file" ] || return

	enabled=$(get_value enabled)
	nwid=$(get_value nwid)
}

read_config

[ -f "$ZT_CLI_BIN" ] || redirect_to "/" "danger" "ZeroTierOne client is not a part of your firmware."
[ -f "$ZT_ONE_BIN" ] || redirect_to "/" "danger" "$ZT_ONE_BIN file not found."

[ -n "$nwid" ] && ZT_NETWORK_CONFIG="/var/lib/zerotier-one/networks.d/${nwid}.conf"

if [ "POST" = "$REQUEST_METHOD" ]; then
	case "$POST_action" in
		create)
			enabled="$POST_enabled"
			nwid="$POST_nwid"

			if [ "true" = "$enabled" ]; then
				error_if_empty "$nwid" "ZeroTier Network ID cannot be empty."
				[ "${#nwid}" -ne 16 ] && set_error_flag "ZeroTier Network ID should be 16 digits long."
			fi

			if [ -z "$error" ]; then
				set_value enabled "$enabled"
				set_value nwid "$nwid"

				jct "$config_file" import "$temp_config_file"
				rm "$temp_config_file"

				update_caminfo
				redirect_back "success" "ZeroTier config updated."
			fi
			;;
		start | open)
			service start zerotier >&2
			redirect_back "success" "Sevice is up"
			;;
		stop | close)
			service stop zerotier >&2
			redirect_back "danger" "Service is down"
			;;
		join)
			$ZT_CLI_BIN join $nwid >&2
			while [ -z $(grep nwid "$ZT_NETWORK_CONFIG") ]; do sleep 1; done
			redirect_back "success" "Joined network $nwid"
			;;
		leave)
			$ZT_CLI_BIN leave $nwid >&2
			redirect_back "success" "Left network $nwid"
			;;
		*)
			redirect_back "danger" "Unknown action $POST_action!"
			;;
	esac
fi
%>
<%in _header.cgi %>

<div class="row g-4 mb-4">
  <div class="col col-lg-4">
    <h3>Settings</h3>
    <form action="<%= $SCRIPT_NAME %>" method="post" class="mb-4">
      <% field_hidden "action" "create" %>
      <% field_text "nwid" "ZeroTier Network ID" 'Get one at <a href="https://my.zerotier.com/">my.zerotier.com</a>' %>
      <% field_switch "enabled" "Join ZeroTier network on boot" %>
      <% button_submit %>
    </form>
  </div>
  <div class="col col-lg-8">
<% if zerotier-cli info >/dev/null ; then %>
    <div class="alert alert-success">
      <h5>ZeroTier Tunnel is open</h5>

<% if [ -f "$ZT_NETWORK_CONFIG" ]; then %>
  <% nwid="$(grep ^nwid= $ZT_NETWORK_CONFIG | cut -d= -f2)" %>
  <% name="$(grep ^n= $ZT_NETWORK_CONFIG | cut -d= -f2)" %>

<% if [ -n "$nwid" ] && [ -n "$name" ]; then %>
      <p>Use the following credentials to set up remote access via active virtual tunnel:</p>
      <dl>
        <dt>NWID: <%= $nwid %></dd>
        <dt>Name: <%= $name %></dd>
      </dl>

      <form action="<%= $SCRIPT_NAME %>" method="post" class="mb-0">
        <% field_hidden "action" "leave" %>
        <% button_submit "Leave network" "danger" %>
      </form>
<% fi %>

<% else %>
      <div class="row">
        <div class="col">
          <form action="<%= $SCRIPT_NAME %>" method="post" class="mb-0">
            <% field_hidden "action" "join" %>
            <% button_submit "Join network" %>
          </form>
        </div>
        <div class="col">
          <form action="<%= $SCRIPT_NAME %>" method="post" class="mb-0">
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
      <form action="<%= $SCRIPT_NAME %>" method="post" class="mb-0">
        <% field_hidden "action" "start" %>
        <% button_submit "Open tunnel" %>
      </form>
    </div>

<% fi %>

  </div>
</div>

<div class="alert alert-dark ui-debug d-none">
<h4 class="mb-3">Debug info</h4>
<% ex "jct $config_file get $domain" %>
<% ex "cat $ZT_NETWORK_CONFIG" %>
<% ex "ps | grep zerotier" %>
</div>


<%in _footer.cgi %>
