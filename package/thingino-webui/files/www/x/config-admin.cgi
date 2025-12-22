#!/bin/haserl
<%in _common.cgi %>
<%
page_title="Admin profile"

domain="admin"
config_file="/etc/thingino.json"
temp_config_file="/tmp/$domain.json"

defaults() {
	default_for name "Thingino Camera Admin"
}

set_value() {
	[ -f "$temp_config_file" ] || echo '{}' > "$temp_config_file"
	local sanitized_value
	sanitized_value="$(sanitize_json_value "$2")"
	jct "$temp_config_file" set "$domain.$1" "$sanitized_value" >/dev/null 2>&1
}

get_value() {
	jct $config_file get "$domain.$1"
}

read_config() {
	[ -f "$config_file" ] || return

	name="$(get_value name)"
	email="$(get_value email)"
	telegram="$(get_value telegram)"
	discord="$(get_value discord)"
}

read_config

if [ "POST" = "$REQUEST_METHOD" ]; then
	error=""

	name="$POST_name"
	email="$POST_email"
	telegram="$POST_telegram"
	discord="$POST_discord"

	# add @ to Discord and Telegram usernames, if missed
	if [ -n "$discord" ]; then
		[ "${discord:0:1}" = "@" ] || discord="@$discord"
	fi

	if [ -n "$telegram" ]; then
		[ "${telegram:0:1}" = "@" ] || telegram="@$telegram"
	fi

	defaults

	if [ -z "$error" ]; then
		set_value name "$name"
		set_value email "$email"
		set_value telegram "$telegram"
		set_value discord "$discord"

		jct "$config_file" import "$temp_config_file"
		rm "$temp_config_file"

		redirect_to $SCRIPT_NAME "success" "Data updated."
	else
		redirect_to $SCRIPT_NAME "danger" "Error: $error"
	fi
fi

defaults
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
<% field_text "name" "Full name" %>
<% field_text "email" "Email address" %>
</div>
<div class="col">
<% field_text "telegram" "Username on Telegram" %>
<% field_text "discord" "Username on Discord" %>
</div>
</div>

<% button_submit %>
</form>

<div class="alert alert-dark ui-debug d-none">
<h4 class="mb-3">Debug info</h4>
<% ex "jct $config_file get $domain" %>
</div>

<%in _footer.cgi %>
