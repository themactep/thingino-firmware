#!/bin/haserl
<%in _common.cgi %>
<%
plugin="webhook"
plugin_name="Send to Webhook"
page_title="Send to Webhook"
params="enabled attach_snapshot url socks5_enabled"

config_file="$ui_config_dir/$plugin.conf"
include $config_file

if [ "POST" = "$REQUEST_METHOD" ]; then
	# parse values from parameters
	read_from_post "$plugin" "$params"

	# validate
	[ "true" = "$webhook_enabled" ] && [ -z "$webhook_url" ] && \
		set_error_flag "Webhook URL cannot be empty."

	if [ -z "$error" ]; then
		tmp_file=$(mktemp)
		for p in $params; do
			echo "${plugin}_$p=\"$(eval echo \$${plugin}_$p)\"" >>$tmp_file
		done; unset p
		mv $tmp_file $config_file

		update_caminfo
		redirect_back "success" "$plugin_name config updated."
	fi

	redirect_to $SCRIPT_NAME
else
	[ -z "$webhook_attach_snapshot" ] && webhook_attach_snapshot="true"
fi
%>
<%in _header.cgi %>

<form action="<%= $SCRIPT_NAME %>" method="post">
<div class="row row-cols-1 row-cols-md-2 row-cols-lg-3 g-4 mb-4">
<div class="col">
<% field_switch "webhook_enabled" "Enable sending to webhook" %>
<% field_text "webhook_url" "Webhook URL" %>
<% field_switch "webhook_attach_snapshot" "Attach Snapshot" %>
<% field_switch "webhook_socks5_enabled" "Use SOCKS5" "$STR_CONFIGURE_SOCKS" %>
</div>
<div class="col">
<% ex "cat $config_file" %>
</div>
</div>
<% button_submit %>
</form>

<%in _footer.cgi %>
