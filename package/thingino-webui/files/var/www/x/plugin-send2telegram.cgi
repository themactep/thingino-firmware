#!/usr/bin/haserl
<%in p/common.cgi %>
<%
plugin="telegram"
plugin_name="Send to Telegram"
page_title="Send to Telegram"
params="enabled token as_attachment as_photo channel caption socks5_enabled"

tmp_file=/tmp/${plugin}.conf

config_file="${ui_config_dir}/${plugin}.conf"
[ ! -f "$config_file" ] && touch $config_file

if [ "POST" = "$REQUEST_METHOD" ]; then
	# parse values from parameters
	for p in $params; do
		eval ${plugin}_${p}=\$POST_${plugin}_${p}
		sanitize "${plugin}_${p}"
	done; unset p

	### Validation
	if [ "true" = "$telegram_enabled" ]; then
		[ -z "$telegram_token"   ] && set_error_flag "Telegram token cannot be empty."
		[ -z "$telegram_channel" ] && set_error_flag "Telegram channel cannot be empty."
	fi

	if [ -z "$error" ]; then
		# create temp config file
		:>$tmp_file
		for p in $params; do
			echo "${plugin}_${p}=\"$(eval echo \$${plugin}_${p})\"" >>$tmp_file
		done; unset p
		mv $tmp_file $config_file

		update_caminfo
		redirect_back "success" "$plugin_name config updated."
	fi

	redirect_to $SCRIPT_NAME
else
	include $config_file

	# Default values
	[ -z "$telegram_caption" ] && telegram_caption="%hostname, %datetime"
fi
%>
<%in p/header.cgi %>

<form action="<%= $SCRIPT_NAME %>" method="post">
<% field_switch "telegram_enabled" "Enable sending to Telegram" %>
<div class="row row-cols-1 row-cols-md-2 row-cols-lg-3 g-4 mb-4">
<div class="col">
<% field_text "telegram_token" "Token" "Your Telegram Bot authentication token." %>
<% field_text "telegram_channel" "Chat ID" "Numeric ID of the channel you want the bot to post images to." %>
<% field_text "telegram_caption" "Photo caption" "Available variables: %hostname, %datetime." %>
</div>
<div class="col">
<% field_switch "telegram_as_attachment" "Send as attachment." %>
<% field_switch "telegram_as_photo" "Send as photo." %>
<% field_switch "telegram_socks5_enabled" "Use SOCKS5" "<a href=\"config-socks5.cgi\">Configure</a> SOCKS5 access" %>
</div>
<div class="col">
<% ex "cat $config_file" %>
</div>
</div>
<% button_submit %>
</form>

<% if [ -z "$telegram_token" ]; then %>
<div class="alert alert-info mt-4">
<h5>To create a channel for your Telegram bot:</h5>
<ol>
<li>Start a chat with <a href=\"https://t.me/BotFather\">@BotFather</a></li>
<li>Enter <code>/start</code> to start a session.</li>
<li>Enter <code>/newbot</code> to create a new bot.</li>
<li>Give your bot channel a name, e.g. <i>cool_cam_bot</i>.</li>
<li>Give your bot a username, e.g. <i>CoolCamBot</i>.</li>
<li>Copy the token assigned to your new bot by the BotFather, and paste it to the form.</li>
</ol>
</div>
<% fi %>

<%in p/footer.cgi %>
