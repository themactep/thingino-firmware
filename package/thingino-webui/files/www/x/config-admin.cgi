#!/bin/haserl
<%in _common.cgi %>
<%
page_title="Admin profile"

if [ "POST" = "$REQUEST_METHOD" ]; then
	error=""

	read_from_post "admin" "name email telegram discord"

	# add @ to Discord and Telegram usernames, if missed
	if [ -n "$admin_discord" ]; then
		[ "${admin_discord:0:1}" = "@" ] || admin_discord="@$admin_discord"
	fi

	if [ -n "$admin_telegram" ]; then
		[ "${admin_telegram:0:1}" = "@" ] || admin_telegram="@$admin_telegram"
	fi

	if [ -z "$error" ]; then
		save2config "
admin_name=\"$admin_name\"
admin_email=\"$admin_email\"
admin_telegram=\"$admin_telegram\"
admin_discord=\"$admin_discord\"
"
	fi
	redirect_to $SCRIPT_NAME
fi
%>
<%in _header.cgi %>

<form action="<%= $SCRIPT_NAME %>" method="post" class="mb-4">
<div class="row row-cols-1 row-cols-md-2 row-cols-lg-3">
<div class="col">
<p class="alert alert-info">Full name and email address of the admin record
will be used as sender identity for emails originating from this camera.</p>
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

<div class="alert alert-dark ui-debug d-none">
<h4 class="mb-3">Debug info</h4>
<% ex "grep ^admin_ $WEB_CONFIG_FILE" %>
</div>

<%in _footer.cgi %>
