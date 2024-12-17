#!/bin/haserl
<%in _common.cgi %>
<%
plugin="webhook"
plugin_name="Send to Webhook"
page_title="Send to Webhook"
params="enabled attach_snapshot payload socks5_enabled url"

config_file="$ui_config_dir/webhook.conf"
include $config_file

if [ "POST" = "$REQUEST_METHOD" ]; then
	read_from_post "webhook" "$params"

	if [ "true" = "$webhook_enabled" ]; then
		error_if_empty "$webhook_url" "Webhook URL cannot be empty."
	fi

	if [ -z "$error" ]; then
		tmp_file=$(mktemp -u)
		for p in $params; do
			echo "webhook_$p=\"$(eval echo \$webhook_$p)\"" >>$tmp_file
		done; unset p
		mv $tmp_file $config_file

		update_caminfo
		redirect_back "success" "$plugin_name config updated."
	fi

	redirect_to $SCRIPT_NAME
fi

default_for webhook_attach_snapshot "true"
%>
<%in _header.cgi %>

<form action="<%= $SCRIPT_NAME %>" method="post" class="mb-4">
<% field_switch "webhook_enabled" "Enable sending to webhook" %>
<div class="row row-cols-1 row-cols-md-2 row-cols-xl-3">
<div class="col">
<% field_text "webhook_url" "Webhook URL" %>
<% field_switch "webhook_socks5_enabled" "Use SOCKS5" "$STR_CONFIGURE_SOCKS" %>
</div>
<div class="col">
<% field_textarea "webhook_payload" "Payload" %>
<% field_switch "webhook_attach_snapshot" "Attach Snapshot" %>
</div>
</div>
<% button_submit %>
</form>

<div class="alert alert-dark ui-debug d-none">
<h4 class="mb-3">Debug info</h4>
<% ex "cat $config_file" %>
</div>

<%in _footer.cgi %>
