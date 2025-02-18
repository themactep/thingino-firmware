#!/bin/haserl
<%in _common.cgi %>
<%
page_title="Telegram Bot"
params="enabled token users"
for i in $(seq 0 9); do
	params="$params command_$i description_$i script_$i"
done

config_file="/etc/webui/telegrambot.conf"
include $config_file

if [ "POST" = "$REQUEST_METHOD" ]; then
	read_from_post "telegrambot" "$params"

	if [ "true" = "$telegrambot_enabled" ]; then
		error_if_empty "$telegrambot_token" "Telegram token cannot be empty."
	fi

	telegrambot_users="${telegrambot_users//[,;]/ }"

	if [ -z "$error" ]; then
		tmp_file=$(mktemp -u)
		[ -f "$config_file" ] && cp "$config_file" "$tmp_file"
		for p in $params; do
			sed -i -r "/^telegrambot_$p=/d" "$tmp_file"
			echo "telegrambot_$p=\"$(eval echo \$telegrambot_$p)\"" >> "$tmp_file"
		done
		mv $tmp_file $config_file

		/etc/init.d/S93telegrambot restart >/dev/null
	fi
	redirect_to $SCRIPT_NAME
fi

for p in $params; do
	sanitize4web "telegrambot_$p"
done; unset p

default_for telegrambot_caption "%hostname, %datetime"
%>
<%in _header.cgi %>

<form action="<%= $SCRIPT_NAME %>" method="post" class="mb-4">
<% field_switch "telegrambot_enabled" "Enable Telegram Bot" %>

<div class="row mb-3">
<div class="col col-lg-6">
<% field_text "telegrambot_token" "Bot Token" "click <span class=\"link\" data-bs-toggle=\"modal\" data-bs-target=\"#helpModal\">here</span> for help" %>
<% field_text "telegrambot_users" "Respond only to these users" "whitespace separated list" %>
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

<div class="alert alert-dark ui-debug d-none">
<h4 class="mb-3">Debug info</h4>
<% ex "cat $config_file" %>
</div>

<%in _tg_bot.cgi %>
<%in _footer.cgi %>
