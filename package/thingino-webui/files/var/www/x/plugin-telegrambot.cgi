#!/bin/haserl
<%in _common.cgi %>
<%
plugin="telegrambot"
plugin_name="Telegram Bot"
page_title="Telegram Bot"

params="enabled token"
for i in $(seq 0 9); do
	params="$params command_$i description_$i script_$i"
done

config_file="$ui_config_dir/$plugin.conf"
include $config_file

if [ "POST" = "$REQUEST_METHOD" ]; then
	read_from_post "$plugin" "$params"

	if [ "true" = "$telegrambot_enabled" ]; then
		error_if_empty "$telegrambot_token" "Telegram token cannot be empty."
	fi

	if [ -z "$error" ]; then
		tmp_file=$(mktemp -u)
		for p in $params; do
			echo "${plugin}_$p=\"$(eval echo \$${plugin}_$p)\"" >>$tmp_file
		done; unset p
		mv $tmp_file $config_file

		update_caminfo
		/etc/init.d/S93telegrambot restart >/dev/null
		redirect_back "success" "$plugin_name config updated."
	fi

	redirect_to $SCRIPT_NAME
fi

for p in $params; do
	sanitize4web "${plugin}_$p"
done; unset p

default_for telegrambot_caption "%hostname, %datetime"
%>
<%in _header.cgi %>

<form action="<%= $SCRIPT_NAME %>" method="post" class="mb-4">
<% field_switch "telegrambot_enabled" "Enable Telegram Bot" %>

<div class="row row-cols-3 mb-3">
<div class="col">
<div class="input-group mb-3">
<input type="text" id="telegrambot_token" name="telegrambot_token" value="<%= $telegrambot_token %>" class="form-control" placeholder="Bot Token" aria-label="Your Telegram Bot authentication token.">
<span class="input-group-text p-0"><button type="button" class="btn" data-bs-toggle="modal" data-bs-target="#helpModal">Help</button></span>
</div>
</div>
</div>

<div class="bot-commands mb-4">
<h5>Bot Commands</h5>
<p class="hint mb-3">Use $chat_id variable for the active chat ID.</p>
<% for i in $(seq 0 9); do %>
<div class="row g-1 mb-3 mb-lg-1">
<div class="col-4 col-lg-2">
<input type="text" class="form-control" id="telegrambot_command_<%= $i %>" name="telegrambot_command_<%= $i %>"
 placeholder="Bot Command" value="<%= $(t_value "telegrambot_command_$i") %>">
</div>
<div class="col-8 col-lg-3">
<input type="text" class="form-control" id="telegrambot_description_<%= $i %>" name="telegrambot_description_<%= $i %>"
 placeholder="Command Description" value="<%= $(t_value "telegrambot_description_$i") %>">
</div>
<div class="col-lg-7">
<input type="text" class="form-control" id="telegrambot_script_<%= $i %>" name="telegrambot_script_<%= $i %>"
 placeholder="Linux Command" value="<%= $(t_value "telegrambot_script_$i") %>">
</div>
</div>
<% done %>
</div>
<% button_submit %>
</form>

<div class="alert alert-dark ui-debug">
<h4 class="mb-3">Debug info</h4>
<% ex "cat $config_file" %>
</div>

<%in _tg_bot.cgi %>
<%in _footer.cgi %>
