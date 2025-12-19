#!/bin/haserl
<%in _common.cgi %>
<%
page_title="Send to Ntfy"

camera_id=${network_macaddr//:/}

domain="ntfy"
config_file="/etc/send2.json"
temp_config_file="/tmp/send2ntfy.json"

defaults() {
	default_for host "ntfy.sh"
	default_for topic "$camera_id"
	default_for message "{\"camera_id\": \"$camera_id\", \"timestamp\": \"%s\"}"
	default_for tags "[]"
	default_for send_photo "false"
	default_for send_video "false"
}

save_config() {
	[ -f "$temp_config_file" ] || echo '{}' > "$temp_config_file"
	jct "$temp_config_file" set "$domain.$1" "$2" >/dev/null 2>&1
}

get_value() {
	jct $config_file get "$domain.$1"
}

read_config() {
	[ -f "$config_file" ] || return

	host=$(get_value "host")
	port=$(get_value "port")
	username=$(get_value "username")
	password=$(get_value "password")
	token=$(get_value "token")
	topic=$(get_value "topic")
	icon=$(get_value "icon")
	message=$(get_value "message")
	title=$(get_value "title")
	tags=$(get_value "tags")
	delay=$(get_value "delay")
	prority=$(get_value "priority")
	send_photo=$(get_value "send_photo")
	send_video=$(get_value "send_video")
	attach=$(get_value "attach")
	click=$(get_value "click")
	filename=$(get_value "filename")
	email=$(get_value "email")
	call=$(get_value "call")
	actions=$(get_value "actions")
	twilio_token=$(get_value "twilio_token")
}

read_config

if [ "POST" = "$REQUEST_METHOD" ]; then
	error=""

	host="$POST_host"
	port="$POST_port"
	username="$POST_username"
	password="$POST_password"
	token="$POST_token"
	topic="$POST_topic"
	message="$POST_message"
	title="$POST_title"
	send_photo="$POST_send_photo"
	send_video="$POST_send_video"

	error_if_empty "$topic" "Ntfy topic cannot be empty."
	error_if_empty "$message" "Ntfy message cannot be empty."

	if [ -n "$(echo $topic | sed -r -n /[^-_a-zA-Z0-9]/p)" ]; then
		set_error_flag "Ntfy topic should not include non-ASCII or special characters like /, #, +, or space."
	fi

	if [ ${#topic} -gt 64 ]; then
		set_error_flag "Ntfy topic should not exceed 64 characters."
	fi

	defaults

	if [ -z "$error" ]; then
		save_config "host" "$host"
		save_config "port" "$port"
		save_config "username" "$username"
		save_config "password" "$password"
		save_config "token" "$token"
		save_config "topic" "$topic"
		save_config "message" "$message"
		save_config "title" "$title"
		#save_config "icon" "$icon"
		#save_config "tags" "$tags"
		#save_config "delay" "$delay"
		#save_config "priority" "$prority"
		#save_config "send_photo" "$send_photo"
		#save_config "send_video" "$send_video"
		#save_config "attach" "$attach"
		#save_config "click" "$click"
		#save_config "filename" "$filename"
		#save_config "email" "$email"
		#save_config "call" "$call"
		#save_config "actions" "$actions"
		#save_config "twilio_token" "$twilio_token"
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
<% field_text "host" "Ntfy server" "Defaults to <a href=\"https://ntfy.sh/\" target=\"_blank\">ntfy.sh</a>" %>
<% field_text "username" "Ntfy username" %>
<% field_password "password" "Ntfy password" %>
<% field_text "token" "Ntfy token" %>
</div>
<div class="col">
<% field_text "topic" "Ntfy topic" %>
<% field_text "title" "Ntfy title" %>
<% field_textarea "message" "Ntfy message" "$STR_SUPPORTS_STRFTIME" %>
<% field_switch "send_photo" "Send photo" %>
<% field_switch "send_video" "Send video" %>
</div>
</div>
<% button_submit %>
</form>

<button type="button" class="btn btn-dark border mb-2" title="Send to Ntfy" data-sendto="ntfy">Test</button>

<div class="alert alert-dark ui-debug d-none">
<h4 class="mb-3">Debug info</h4>
<% ex "jct $config_file get ntfy" %>
</div>

<script>
$('#message').style.height = '7rem';
</script>

<%in _footer.cgi %>
