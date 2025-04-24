#!/bin/haserl
<%in _common.cgi %>
<%
page_title="Send to Telegram"

defaults() {
	default_for telegram_attach_snapshot "true"
	default_for telegram_attach_video "true"
	default_for telegram_caption "%hostname, %datetime"
}

if [ "POST" = "$REQUEST_METHOD" ]; then
	error=""

	read_from_post "telegram" "token attach_snapshot attach_video channel caption"

	error_if_empty "$telegram_token" "Telegram token cannot be empty."
	error_if_empty "$telegram_channel" "Telegram channel cannot be empty."

	defaults

	if [ -z "$error" ]; then
		save2config "
telegram_attach_snapshot=\"$telegram_attach_snapshot\"
telegram_attach_video=\"$telegram_attach_video\"
telegram_caption=\"$telegram_caption\"
telegram_channel=\"$telegram_channel\"
telegram_token=\"$telegram_token\"
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
<div class="input-group mb-3">
<input type="text" id="telegram_token" name="telegram_token" value="<%= $telegram_token %>" class="form-control" placeholder="Bot Token" aria-label="Your Telegram Bot authentication token.">
<span class="input-group-text p-0"><button type="button" class="btn" data-bs-toggle="modal" data-bs-target="#helpModal">Help</button></span>
</div>
<% field_text "telegram_channel" "Chat ID" "ID of the channel to post images to." "-100xxxxxxxxxxxx" %>
</div>
<div class="col">
<% field_text "telegram_caption" "Photo caption" "Available variables: %hostname, %datetime" %>
<p class="label">Attachment</p>
<% field_switch "telegram_attach_snapshot" "Attach snapshot" %>
<% field_switch "telegram_attach_video" "Attach video" %>
</div>
</div>
<% button_submit %>
</form>

<button type="button" class="btn btn-dark border mb-2" title="Send to Telegram" data-sendto="telegram">Test</button>

<div class="alert alert-dark ui-debug d-none">
<h4 class="mb-3">Debug info</h4>
<% ex "grep ^telegram_ $CONFIG_FILE" %>
</div>

<%in _tg_bot.cgi %>
<%in _footer.cgi %>
