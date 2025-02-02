#!/bin/haserl
<%in _common.cgi %>
<%
plugin="webhook"
plugin_name="Send to Webhook"
page_title="Send to Webhook"
params="attach_snapshot payload url"

config_file="$ui_config_dir/webhook.conf"
include $config_file

defaults() {
	default_for webhook_attach_snapshot "true"
}

if [ "POST" = "$REQUEST_METHOD" ]; then
	read_from_post "webhook" "$params"

	error_if_empty "$webhook_url" "Webhook URL cannot be empty."

	defaults

	if [ -z "$error" ]; then
		tmp_file=$(mktemp -u)
		[ -f "$config_file" ] && cp "$config_file" "$tmp_file"
		for p in $params; do
			sed -i -r "/^webhook_$p=/d" "$tmp_file"
			echo "webhook_$p=\"$(eval echo \$webhook_$p)\"" >> "$tmp_file"
		done
		mv $tmp_file $config_file
	fi
	redirect_to $SCRIPT_NAME
fi

defaults
%>
<%in _header.cgi %>

<form action="<%= $SCRIPT_NAME %>" method="post" class="mb-4">
<div class="row row-cols-1 row-cols-md-2 row-cols-xl-3">
<div class="col">
<% field_text "webhook_url" "Webhook URL" %>
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
