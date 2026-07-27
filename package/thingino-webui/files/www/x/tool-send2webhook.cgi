#!/bin/haserl
<%in _common.cgi %>
<%
page_title="Send to Webhook"

defaults() {
	default_for send_photo "true"
	default_for send_video "false"
}

read_config() {
	local CONFIG_FILE=/etc/send2.json
	[ -f "$CONFIG_FILE" ] || return

	url=$(jct $CONFIG_FILE get webhook.url)
	message=$(jct $CONFIG_FILE get webhook.message)
	send_photo=$(jct $CONFIG_FILE get webhook.send_photo)
	send_video=$(jct $CONFIG_FILE get webhook.send_video)
}

read_config

if [ "POST" = "$REQUEST_METHOD" ]; then
	error=""

	url="$POST_url"
	message="$POST_message"
	send_photo="$POST_send_photo"
	send_video="$POST_send_video"

	error_if_empty "$url" "Webhook URL cannot be empty."

	defaults

	if [ -z "$error" ]; then
                tmpfile="$(mktemp -u).json"
                jct $tmpfile set webhook.url "$url"
                jct $tmpfile set webhook.message "$message"
                jct $tmpfile set webhook.send_photo "$send_photo"
                jct $tmpfile set webhook.send_video "$send_video"
                jct /etc/send2.json import $tmpfile
                rm $tmpfile

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
<% field_text "url" "Webhook URL" %>
</div>
<div class="col">
<% field_textarea "message" "Message" %>
<% field_switch "send_photo" "Attach Snapshot" %>
<% field_switch "send_video" "Attach Videoclips" %>
</div>
</div>
<% button_submit %>
</form>

<div class="alert alert-dark ui-debug d-none">
<h4 class="mb-3">Debug info</h4>
<% ex "jct /etc/send2.json get webhook" %>
</div>

<button type="button" class="btn btn-dark border mb-2" title="Send to Webhook" data-sendto="webhook">Test</button>

<%in _footer.cgi %>
