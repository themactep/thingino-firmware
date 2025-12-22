#!/bin/haserl
<%in _common.cgi %>
<%
page_title="Send to Telegram"
domain="telegram"
config_file="/etc/send2.json"
temp_config_file="/tmp/$domain.json"

defaults() {
	default_for caption "%hostname, %datetime"
	default_for send_photo "false"
	default_for send_video "false"
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

	token=$(get_value "token")
	channel=$(get_value "channel")
	message=$(get_value "message")
	file=$(get_value "file")
	silent=$(get_value "silent")
	send_photo=$(get_value "send_photo")
	send_video=$(get_value "send_video")
}

read_config

if [ "POST" = "$REQUEST_METHOD" ]; then
	error=""

	token="$POST_token"
	channel="$POST_channel"
	caption="$POST_caption"
	send_photo="$POST_send_photo"
	send_video="$POST_send_video"

	error_if_empty "$token" "Telegram token cannot be empty."
	error_if_empty "$channel" "Telegram channel cannot be empty."

	defaults

	if [ -z "$error" ]; then
		set_value token "$token"
		set_value channel "$channel"
		set_value caption "$caption"
		set_value send_photo "$send_photo"
		set_value send_video "$send_video"

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
<div class="row row-cols-1 row-cols-md-2 row-cols-xl-3">
<div class="col">
<% field_text "token" "Telegram Bot Token" %>
<% field_text "channel" "Chat ID" "ID of the channel to post images to." "-100xxxxxxxxxxxx" %>
</div>
<div class="col">
<% field_text "caption" "Photo caption" "Available variables: %hostname, %datetime" %>
<p class="label">Attachment</p>
<% field_switch "send_photo" "Send photo" %>
<% field_switch "send_video" "Send video" %>
</div>
<div class="col">
<button type="button" class="btn" data-bs-toggle="modal" data-bs-target="#helpModal">Help</button>
<%in _tg_bot.cgi %>
</div>
</div>
<% button_submit %>
</form>

<button type="button" class="btn btn-dark border mb-2" title="Send to Telegram" data-sendto="telegram">Test</button>

<div class="alert alert-dark ui-debug d-none">
<h4 class="mb-3">Debug info</h4>
<% ex "jct $config_file get $domain" %>
</div>

<%in _footer.cgi %>
