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
	# parse values from parameters
	read_from_post "$plugin" "$params"

	# validate
	if [ "true" = "$telegrambot_enabled" ]; then
		error_if_empty "$telegrambot_token" "Telegram token cannot be empty."
	fi

	if [ -z "$error" ]; then
		tmp_file=$(mktemp)
		for p in $params; do
			echo "${plugin}_$p=\"$(eval echo \$${plugin}_$p)\"" >>$tmp_file
		done; unset p
		mv $tmp_file $config_file

		update_caminfo
		/etc/init.d/S93telegrambot restart >/dev/null
		redirect_back "success" "$plugin_name config updated."
	fi

	redirect_to $SCRIPT_NAME
else
	for p in $params; do
		sanitize4web "${plugin}_$p"
	done; unset p

	# Default values
	default_for telegrambot_caption "%hostname, %datetime"
fi
%>
<%in _header.cgi %>

<div class="row g-4 mb-4">
<div class="col">
<form action="<%= $SCRIPT_NAME %>" method="post" class="mb-4">

<% field_switch "telegrambot_enabled" "Enable Telegram Bot" %>

<div class="input-group mb-3">
<input type="text" id="telegrambot_token" name="telegrambot_token" value="<%= $telegrambot_token %>"
 class="form-control" placeholder="Bot Token" aria-label="Your Telegram Bot authentication token.">
<span class="input-group-text">
<button type="button" class="btn" data-bs-toggle="modal" data-bs-target="#helpModal">Help</button>
</span>
</div>
<div class="bot-commands mb-4">
<h5>Bot Commands</h5>
<p class="hint mb-3">Use $chat_id variable for the active chat ID.</p>
<% for i in $(seq 0 9); do %>
<div class="row g-1 mb-3 mb-lg-1">
<div class="col-4 col-lg-2">
<input type="text" id="telegrambot_command_<%= $i %>" name="telegrambot_command_<%= $i %>" class="form-control"
 placeholder="Bot Command" value="<%= $(t_value "telegrambot_command_$i") %>">
</div>
<div class="col-8 col-lg-3">
<input type="text" id="telegrambot_description_<%= $i %>" name="telegrambot_description_<%= $i %>" class="form-control"
 placeholder="Command Description" value="<%= $(t_value "telegrambot_description_$i") %>">
</div>
<div class="col-lg-7">
<input type="text" id="telegrambot_script_<%= $i %>" name="telegrambot_script_<%= $i %>" class="form-control"
 placeholder="Linux Command" value="<%= $(t_value "telegrambot_script_$i") %>">
</div>
</div>
<% done %>
</div>
<% button_submit %>
</form>
</div>
</div>

<div class="ui-expert">
<% ex "cat $config_file" %>
</div>

<div class="modal fade" id="helpModal" tabindex="-1">
<div class="modal-dialog">
<div class="modal-content">
<div class="modal-header">
<h5 class="modal-title">To create a Telegram bot</h5>
<button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
</div>
<div class="modal-body">
<ol>
<li>Start a chat with <a href="https://t.me/BotFather">@BotFather</a></li>
<li>Enter <code>/start</code> to start a session.</li>
<li>Enter <code>/newbot</code> to create a new bot.</li>
<li>Give your bot channel a name, e.g. <i>cool_cam_bot</i>.</li>
<li>Give your bot a username, e.g. <i>CoolCamBot</i>.</li>
<li>Copy the token assigned to your new bot by the BotFather, and paste it to the form.</li>
</ol>
</div>
<div class="modal-footer">
<button type="button" class="btn btn-secondary" data-bs-dismiss="modal">Close</button>
</div>
</div>
</div>
</div>

<%in _footer.cgi %>
