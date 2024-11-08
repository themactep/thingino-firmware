#!/bin/haserl
<%in _common.cgi %>
<%
plugin="admin"
page_title="Admin profile"
params="name email telegram discord"

config_file="$ui_config_dir/$plugin.conf"
include $config_file

if [ "POST" = "$REQUEST_METHOD" ]; then
	# parse values from parameters
	read_from_post "$plugin" "$params"

	error_if_empty "$admin_name" "Name cannot be empty."
	error_if_empty "$admin_email" "Email cannot be empty."
	# error_if_empty "$admin_telegram" "Telegram username cannot be empty."
	# error_if_empty "$admin_discord" "Discord username cannot be empty."

	# add @ to Discord and Telegram usernames, if missed
	[ -n "$admin_discord" ] && [ "${admin_discord:0:1}" != "@" ] && admin_discord="@$admin_discord"
	[ -n "$admin_telegram" ] && [ "${admin_telegram:0:1}" != "@" ] && admin_telegram="@$admin_telegram"

	if [ -z "$error" ]; then
		# create temp config file
		tmp_file=$(mktemp)
		for p in $params; do
			echo "${plugin}_$p=\"$(eval echo \$${plugin}_$p)\"" >>$tmp_file
		done; unset p
		mv $tmp_file $config_file

		update_caminfo
		redirect_back "success" "Admin profile updated."
	fi
fi
%>
<%in _header.cgi %>

<div class="row row-cols-1 row-cols-md-2 row-cols-lg-3 g-4 mb-4">
<div class="col">
<form action="<%= $SCRIPT_NAME %>" method="post">
<% field_hidden "action" "update" %>
<% field_text "admin_name" "Full name" %>
<% field_text "admin_email" "Email address" %>
<p class="small">Full name and email address above will be used as sender for emails originating from the camera.</p>
<% button_submit %>
</div>
<div class="col">
<% field_text "admin_telegram" "Username on Telegram" %>
<% field_text "admin_discord" "Username on Discord" %>
</form>
</div>
<div class="col">
<% ex "cat $config_file" %>
</div>
</div>

<%in _footer.cgi %>
