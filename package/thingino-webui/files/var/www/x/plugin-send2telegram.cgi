#!/bin/haserl
<%in _common.cgi %>
<%
plugin="telegram"
plugin_name="Send to Telegram"
page_title="Send to Telegram"
params="enabled token as_attachment as_photo channel caption socks5_enabled"

config_file="$ui_config_dir/$plugin.conf"
include $config_file

if [ "POST" = "$REQUEST_METHOD" ]; then
	read_from_post "$plugin" "$params"

	if [ "true" = "$telegram_enabled" ]; then
		error_if_empty "$telegram_token" "Telegram token cannot be empty."
		error_if_empty "$telegram_channel" "Telegram channel cannot be empty."
	fi

	if [ -z "$error" ]; then
		tmp_file=$(mktemp -u)
		for p in $params; do
			echo "${plugin}_$p=\"$(eval echo \$${plugin}_$p)\"" >>$tmp_file
		done; unset p
		mv $tmp_file $config_file

		update_caminfo
		redirect_back "success" "$plugin_name config updated."
	fi

	redirect_to $SCRIPT_NAME
else
	# Default values
	default_for telegram_caption "%hostname, %datetime"
fi
%>
<%in _header.cgi %>

<form action="<%= $SCRIPT_NAME %>" method="post" class="mb-4">
<% field_switch "telegram_enabled" "Enable sending to Telegram" %>
<div class="row row-cols-1 row-cols-md-2 row-cols-xl-3">
<div class="col">
<div class="input-group mb-3">
<input type="text" id="telegram_token" name="telegram_token" value="<%= $telegram_token %>" class="form-control" placeholder="Bot Token" aria-label="Your Telegram Bot authentication token.">
<span class="input-group-text p-0"><button type="button" class="btn" data-bs-toggle="modal" data-bs-target="#helpModal">Help</button></span>
</div>
<% field_text "telegram_channel" "Chat ID" "ID of the channel to post images to." "-100xxxxxxxxxxxx" %>
<% field_switch "telegram_socks5_enabled" "Use SOCKS5" "$STR_CONFIGURE_SOCKS" %>
</div>
<div class="col">
<% field_text "telegram_caption" "Photo caption" "Available variables: %hostname, %datetime." %>
<% field_switch "telegram_as_attachment" "Send as attachment." %>
<% field_switch "telegram_as_photo" "Send as photo." %>
</div>
</div>
<% button_submit %>
</form>

<div class="alert alert-dark ui-debug">
<h4 class="mb-3">Debug info</h4>
<% ex "cat $config_file" %>
</div>

<%in _tg_bot.cgi %>
<%in _footer.cgi %>
