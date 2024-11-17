#!/bin/haserl
<%in _common.cgi %>
<%
plugin="admin"
page_title="Admin profile"
params="name email telegram discord"

config_file="$ui_config_dir/$plugin.conf"
include $config_file

if [ "POST" = "$REQUEST_METHOD" ]; then
	read_from_post "$plugin" "$params"

	# add @ to Discord and Telegram usernames, if missed
	[ -n "$admin_discord" ] && [ "${admin_discord:0:1}" != "@" ] && admin_discord="@$admin_discord"
	[ -n "$admin_telegram" ] && [ "${admin_telegram:0:1}" != "@" ] && admin_telegram="@$admin_telegram"

	if [ -z "$error" ]; then
		tmp_file=$(mktemp -u)
		for p in $params; do
			echo "${plugin}_$p=\"$(eval echo \$${plugin}_$p)\"" >>$tmp_file
		done; unset p
		mv $tmp_file $config_file

		update_caminfo
		redirect_back "success" "Data updated"
	fi
fi
%>
<%in _header.cgi %>

<form action="<%= $SCRIPT_NAME %>" method="post" class="mb-4">
<div class="row row-cols-1 row-cols-md-2 row-cols-lg-3">
<div class="col">
<p class="alert alert-info">Full name and email address of the admin record will be used as sender identity for emails originating from this camera.</p>
</div>
<div class="col">
<% field_hidden "action" "update" %>
<% field_text "admin_name" "Full name" %>
<% field_text "admin_email" "Email address" %>
</div>
<div class="col">
<% field_text "admin_telegram" "Username on Telegram" %>
<% field_text "admin_discord" "Username on Discord" %>
</div>
</div>
<% button_submit %>
</form>

<div class="alert alert-dark ui-debug">
<h4 class="mb-3">Debug info</h4>
<% ex "cat $config_file" %>
</div>

<%in _footer.cgi %>
