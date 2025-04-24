#!/bin/haserl
<%in _common.cgi %>
<%
page_title="Send to Webhook"

defaults() {
	default_for webhook_attach_snapshot "true"
}

if [ "POST" = "$REQUEST_METHOD" ]; then
	error=""

	read_from_post "webhook" "attach_snapshot message url"

	error_if_empty "$webhook_url" "Webhook URL cannot be empty."

	defaults

	if [ -z "$error" ]; then
		save2config "
webhook_attach_snapshot=\"$webhook_attach_snapshot\"
webhook_message=\"$webhook_message\"
webhook_url=\"$webhook_url\"
"
		redirect_to $SCRIPT_NAME "success" "Data updated."
	else
		redirect_to $SCRIPT_NAME "danger" "Error: $error"
	fi
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
<% field_textarea "webhook_message" "Message" %>
<% field_switch "webhook_attach_snapshot" "Attach Snapshot" %>
</div>
</div>
<% button_submit %>
</form>

<div class="alert alert-dark ui-debug d-none">
<h4 class="mb-3">Debug info</h4>
<% ex "grep ^webhook_ $CONFIG_FILE" %>
</div>

<button type="button" class="btn btn-dark border mb-2" title="Send to Webhook" data-sendto="webhook">Test</button>

<%in _footer.cgi %>
