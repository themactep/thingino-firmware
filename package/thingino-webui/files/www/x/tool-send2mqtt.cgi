#!/bin/haserl
<%in _common.cgi %>
<%
page_title="Send to MQTT"

domain="mqtt"
config_file="/etc/send2.json"
temp_config_file="/tmp/$domain.json"

if [ ! -f /usr/bin/mosquitto_pub ]; then
	redirect_to "/" "danger" "MQTT client is not a part of your firmware."
fi

camera_id=${network_macaddr//:/}

defaults() {
	default_for client_id "$camera_id"
	default_for port "1883"
	default_for topic "thingino/$client_id"
	default_for message "{\"camera_id\": \"$camera_id\", \"timestamp\": \"%s\"}"
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

	host=$(get_value "host")
	message=$(get_value "message")
	password=$(get_value "password")
	port=$(get_value "port")
	send_photo=$(get_value "send_photo")
	send_video=$(get_value "send_video")
	topic=$(get_value "topic")
	topic_photo=$(get_value "topic_photo")
	topic_video=$(get_value "topic_video")
	use_ssl=$(get_value "use_ssl")
	username=$(get_value "username")
}

read_config

if [ "POST" = "$REQUEST_METHOD" ]; then
	error=""

	client_id="$POST_client_id"
	host="$POST_host"
	message="$POST_message"
	password="$POST_password"
	port="$POST_port"
	send_photo="$POST_send_photo"
	send_video="$POST_send_video"
	topic="$POST_topic"
	topic_photo="$POST_topic_photo"
	topic_video="$POST_topic_video"
	use_ssl="$POST_use_ssl"
	username="$POST_username"

	error_if_empty "$host" "MQTT broker host cannot be empty."
	error_if_empty "$port" "MQTT port cannot be empty."
	error_if_empty "$topic" "MQTT topic cannot be empty."
	error_if_empty "$message" "MQTT message cannot be empty."

	if [ "${topic:0:1}" = "/" ] || [ "${mqtt_topic_photo:0:1}" = "/" ]; then
		set_error_flag "MQTT topic should not start with a slash."
	fi

	if [ "$topic" != "${topic// /}" ] || [ "$topic_photo" != "${topic_photo// /}" ]; then
		set_error_flag "MQTT topic should not contain spaces."
	fi

	if [ -n "$(echo $topic | sed -r -n /[^a-zA-Z0-9/_-]/p)" ] || \
	   [ -n "$(echo $topic_photo | sed -r -n /[^a-zA-Z0-9/_-]/p)" ]; then
		set_error_flag "MQTT topic should not include non-ASCII or special characters like /, #, +."
	fi

	if [ "true" = "$send_photo" ] && [ -z "$topic_photo" ]; then
		set_error_flag "MQTT topic for snapshot should not be empty."
	fi

	defaults

	if [ -z "$error" ]; then
		set_value host "$host"
		set_value port "$port"
		set_value username "$username"
		set_value password "$password"
		set_value client_id "$client_id"
		set_value topic "$topic"
		set_value message "$message"
		set_value use_ssl "$use_ssl"
		set_value send_photo "$send_photo"
		set_value send_video "$send_video"
		set_value topic_photo "$topic_photo"
		set_value topic_video "$topic_video"

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
<% field_text "client_id" "MQTT client ID" %>
<div class="row g-1">
<div class="col-10"><% field_text "host" "MQTT broker FQDN or IP address" %></div>
<div class="col-2"><% field_text "port" "Port" %></div>
</div>
<% field_text "username" "MQTT broker username" %>
<% field_password "password" "MQTT broker password" %>
<% field_switch "use_ssl" "Use SSL" %>
</div>
<div class="col">
<% field_text "topic" "MQTT topic" %>
<% field_textarea "message" "MQTT message" "$STR_SUPPORTS_STRFTIME" %>
<% field_switch "send_photo" "Send photo" %>
<% field_text "topic_photo" "MQTT topic to send the photo to" %>
<% field_switch "send_video" "Send video" %>
<% field_text "topic_video" "MQTT topic to send the video to" %>
</div>
</div>
<% button_submit %>
</form>

<button type="button" class="btn btn-dark border mb-2" title="Send to MQTT" data-sendto="mqtt">Test</button>

<div class="alert alert-dark ui-debug d-none">
<h4 class="mb-3">Debug info</h4>
<% ex "jct $config_file get $domain" %>
</div>

<script>
$('#message').style.height = '7rem';
$('#use_ssl').addEventListener('change', ev => {
	const el=$('#port');
	if (ev.target.checked) {
		if (el.value === '1883') el.value='8883';
	} else {
		if (el.value === '8883') el.value='1883';
	}
});
</script>

<%in _footer.cgi %>
