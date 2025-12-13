#!/bin/haserl
<%in _common.cgi %>
<%
page_title="Send to Ntfy"

camera_id=${network_macaddr//:/}

defaults() {
	default_for host "ntfy.sh"
	default_for topic "$camera_id"
	default_for message "{\"camera_id\": \"$camera_id\", \"timestamp\": \"%s\"}"
	default_for tags "[]"
	default_for send_photo "false"
	default_for send_video "false"
}

read_config() {
	local CONFIG_FILE=/etc/send2.json
	[ -f "$CONFIG_FILE" ] || return

	        host=$(jct $CONFIG_FILE get ntfy.host)
	        port=$(jct $CONFIG_FILE get ntfy.port)
	    username=$(jct $CONFIG_FILE get ntfy.username)
	    password=$(jct $CONFIG_FILE get ntfy.password)
	       token=$(jct $CONFIG_FILE get ntfy.token)
	       topic=$(jct $CONFIG_FILE get ntfy.topic)
	        icon=$(jct $CONFIG_FILE get ntfy.icon)
	     message=$(jct $CONFIG_FILE get ntfy.message)
	       title=$(jct $CONFIG_FILE get ntfy.title)
	        tags=$(jct $CONFIG_FILE get ntfy.tags)
	       delay=$(jct $CONFIG_FILE get ntfy.delay)
	     prority=$(jct $CONFIG_FILE get ntfy.priority)
	  send_photo=$(jct $CONFIG_FILE get ntfy.send_photo)
	  send_video=$(jct $CONFIG_FILE get ntfy.send_video)
	      attach=$(jct $CONFIG_FILE get ntfy.attach)
	       click=$(jct $CONFIG_FILE get ntfy.click)
	    filename=$(jct $CONFIG_FILE get ntfy.filename)
	       email=$(jct $CONFIG_FILE get ntfy.email)
	        call=$(jct $CONFIG_FILE get ntfy.call)
	     actions=$(jct $CONFIG_FILE get ntfy.actions)
	twilio_token=$(jct $CONFIG_FILE get ntfy.twilio_token)
}

read_config

if [ "POST" = "$REQUEST_METHOD" ]; then
	error=""

	host="$POST_host"
	username="$POST_port"
	password="$POST_password"
	topic="$POST_topic"
	title="$POST_title"
	message="$POST_message"
	send_photo="$POST_send_photo"
	send_video="$POST_send_video"

	# error_if_empty "$host" "Ntfy broker host cannot be empty."
	# error_if_empty "$username" "Ntfy username cannot be empty."
	# error_if_empty "$password" "Ntfy password cannot be empty."
	# error_if_empty "$token" "Ntfy token cannot be empty."
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
		tmpfile="$(mktemp -u).json"
		echo '{}' > $tmpfile
		jct $tmpfile set mqtt.host "$host"
		jct $tmpfile set mqtt.port "$port"
		jct $tmpfile set mqtt.username "$username"
		jct $tmpfile set mqtt.password "$password"
		jct $tmpfile set mqtt.topic "$topic"
		jct $tmpfile set mqtt.title "$title"
		jct $tmpfile set mqtt.message "$message"
		jct $tmpfile set mqtt.send_photo "$send_photo"
		jct $tmpfile set mqtt.send_video "$send_video"
		jct /etc/send2.json import $tmpfile
		rm $tmpfile

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
<% ex "jct /etc/send2.json get ntfy" %>
</div>

<script>
$('#message').style.height = '7rem';
</script>

<%in _footer.cgi %>
