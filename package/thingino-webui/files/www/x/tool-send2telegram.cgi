#!/bin/haserl
<%in _common.cgi %>
<%
page_title="Send to Telegram"

defaults() {
	default_for caption "%hostname, %datetime"
	default_for send_photo "false"
	default_for send_video "false"
}

read_config() {
	local CONFIG_FILE=/etc/send2.json
	[ -f "$CONFIG_FILE" ] || return

	     token=$(jct $CONFIG_FILE get telegram.token)
	   channel=$(jct $CONFIG_FILE get telegram.channel)
	   message=$(jct $CONFIG_FILE get telegram.message)
	      file=$(jct $CONFIG_FILE get telegram.file)
	    silent=$(jct $CONFIG_FILE get telegram.silent)
	send_photo=$(jct $CONFIG_FILE get telegram.send_photo)
	send_video=$(jct $CONFIG_FILE get telegram.send_video)
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
		tmpfile="$(mktemp -u).json"
		jct $tmpfile set telegram.token "$token"
		jct $tmpfile set telegram.channel "$channel"
		jct $tmpfile set telegram.caption "$caption"
		jct $tmpfile set telegram.send_photo "$send_photo"
		jct $tmpfile set telegram.send_video "$send_video"
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
<% ex "jct /etc/send2.json get telegram" %>
</div>

<%in _footer.cgi %>
