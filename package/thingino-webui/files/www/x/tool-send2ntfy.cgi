#!/bin/haserl
<%in _common.cgi %>
<%
page_title="Send to Ntfy"

camera_id=${network_macaddr//:/}

defaults() {
	default_for ntfy_topic "$camera_id"
	default_for ntfy_message "{\"camera_id\": \"$camera_id\", \"timestamp\": \"%s\"}"
}

if [ "POST" = "$REQUEST_METHOD" ]; then
	error=""

	read_from_post "ntfy" "host username password title topic message send_snap"

	# error_if_empty "$ntfy_host" "Ntfy broker host cannot be empty."
	# error_if_empty "$ntfy_username" "Ntfy username cannot be empty."
	# error_if_empty "$ntfy_password" "Ntfy password cannot be empty."
	error_if_empty "$ntfy_topic" "Ntfy topic cannot be empty."
	error_if_empty "$ntfy_message" "Ntfy message cannot be empty."

	if [ -n "$(echo $ntfy_topic | sed -r -n /[^a-zA-Z0-9]/p)" ]; then
		set_error_flag "Ntfy topic should not include non-ASCII characters or special characters like /, #, +, or space."
	fi

	if [ ${#ntfy_topic} -gt 64 ]; then
		set_error_flag "Ntfy topic should not exceed 64 characters."
	fi

	defaults

	if [ -z "$error" ]; then
		save2config "
ntfy_host=\"$ntfy_host\"
ntfy_message=\"$ntfy_message\"
ntfy_password=\"$ntfy_password\"
ntfy_send_snap=\"$ntfy_send_snap\"
ntfy_title=\"$ntfy_title\"
ntfy_topic=\"$ntfy_topic\"
ntfy_username=\"$ntfy_username\"
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
<div class="row row-cols-1 row-cols-md-2 row-cols-lg-3">
<div class="col">
<% field_text "ntfy_host" "Ntfy server" "Defaults to <a href=\"https://ntfy.sh/\" target=\"_blank\">ntfy.sh</a>" %>
<% field_text "ntfy_username" "Ntfy username" %>
<% field_password "ntfy_password" "Ntfy password" %>
</div>
<div class="col">
<% field_text "ntfy_topic" "Ntfy topic" %>
<% field_text "ntfy_title" "Ntfy title" %>
<% field_textarea "ntfy_message" "Ntfy message" "$STR_SUPPORTS_STRFTIME" %>
<% field_switch "ntfy_send_snap" "Send a snapshot" %>
</div>
</div>
<% button_submit %>
</form>

<button type="button" class="btn btn-dark border mb-2" title="Send to Ntfy" data-sendto="ntfy">Test</button>

<div class="alert alert-dark ui-debug d-none">
<h4 class="mb-3">Debug info</h4>
<% ex "grep ^ntfy_ $CONFIG_FILE" %>
</div>

<script>
$('#ntfy_message').style.height = '7rem';
</script>

<%in _footer.cgi %>
