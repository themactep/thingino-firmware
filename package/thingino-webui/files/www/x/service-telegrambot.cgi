#!/bin/haserl
<%in _common.cgi %>
<%
page_title="Telegram Bot"

params="enabled token users"
for i in $(seq 0 9); do
	params="$params command_$i description_$i script_$i"
done

defaults() {
	true
}

if [ "POST" = "$REQUEST_METHOD" ]; then
	read_from_post "telegrambot" "$params"

	for i in $(seq 0 9); do
		sanitize "telegrambot_command_$i"
	done

	telegrambot_users="${telegrambot_users//[,;]/ }"

	if [ "true" = "$telegrambot_enabled" ]; then
		error_if_empty "$telegrambot_token" "Telegram token cannot be empty."
	fi

	if [ -z "$error" ]; then
		save2config "
telegrambot_enabled=\"$telegrambot_enabled\"
telegrambot_token=\"$telegrambot_token\"
telegrambot_users=\"$telegrambot_users\"
telegrambot_command_0=\"$telegrambot_command_0\"
telegrambot_command_1=\"$telegrambot_command_1\"
telegrambot_command_2=\"$telegrambot_command_2\"
telegrambot_command_3=\"$telegrambot_command_3\"
telegrambot_command_4=\"$telegrambot_command_4\"
telegrambot_command_5=\"$telegrambot_command_5\"
telegrambot_command_6=\"$telegrambot_command_6\"
telegrambot_command_7=\"$telegrambot_command_7\"
telegrambot_command_8=\"$telegrambot_command_8\"
telegrambot_command_9=\"$telegrambot_command_9\"
telegrambot_description_0=\"$telegrambot_description_0\"
telegrambot_description_1=\"$telegrambot_description_1\"
telegrambot_description_2=\"$telegrambot_description_2\"
telegrambot_description_3=\"$telegrambot_description_3\"
telegrambot_description_4=\"$telegrambot_description_4\"
telegrambot_description_5=\"$telegrambot_description_5\"
telegrambot_description_6=\"$telegrambot_description_6\"
telegrambot_description_7=\"$telegrambot_description_7\"
telegrambot_description_8=\"$telegrambot_description_8\"
telegrambot_description_9=\"$telegrambot_description_9\"
telegrambot_script_0=\"$telegrambot_script_0\"
telegrambot_script_1=\"$telegrambot_script_1\"
telegrambot_script_2=\"$telegrambot_script_2\"
telegrambot_script_3=\"$telegrambot_script_3\"
telegrambot_script_4=\"$telegrambot_script_4\"
telegrambot_script_5=\"$telegrambot_script_5\"
telegrambot_script_6=\"$telegrambot_script_6\"
telegrambot_script_7=\"$telegrambot_script_7\"
telegrambot_script_8=\"$telegrambot_script_8\"
telegrambot_script_9=\"$telegrambot_script_9\"
"
		/etc/init.d/S93telegrambot restart >/dev/null
		redirect_to $SCRIPT_NAME "success" "Data updated."
	else
		redirect_to $SCRIPT_NAME "danger" "Error: $error"
	fi
fi

for p in $params; do
	sanitize4web "telegrambot_$p"
done

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
<% ex "grep ^telegrambot_ $CONFIG_FILE" %>
</div>

<%in _tg_bot.cgi %>
<%in _footer.cgi %>
