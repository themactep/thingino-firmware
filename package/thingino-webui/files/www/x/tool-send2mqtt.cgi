#!/bin/haserl
<%in _common.cgi %>
<%
page_title="Send to MQTT"

if [ ! -f /usr/bin/mosquitto_pub ]; then
	redirect_to "/" "danger" "MQTT client is not a part of your firmware."
fi

camera_id=${network_macaddr//:/}

defaults() {
	default_for client_id $camera_id
	default_for port "1883"
	default_for topic "thingino/$client_id"
	default_for message "{\"camera_id\": \"$camera_id\", \"timestamp\": \"%s\"}"
}

read_config() {
        local CONFIG_NAME=/etc/send2.json
        [ -f "$CONFIG_NAME" ] || return

               host=$(jct $CONFIG_NAME get mqtt.host)
               port=$(jct $CONFIG_NAME get mqtt.port)
           username=$(jct $CONFIG_NAME get mqtt.username)
           password=$(jct $CONFIG_NAME get mqtt.password)
              topic=$(jct $CONFIG_NAME get mqtt.topic)
            message=$(jct $CONFIG_NAME get mqtt.message)
            is_json=$(jct $CONFIG_NAME get mqtt.is_json)
        topic_photo=$(jct $CONFIG_NAME get mqtt.topic_photo)
         send_photo=$(jct $CONFIG_NAME get mqtt.send_photo)
}

read_config

if [ "POST" = "$REQUEST_METHOD" ]; then
	error=""

	host="$POST_host"
	port="$POST_port"
	client_id="$POST_client_id"
	username="$POST_username"
	password="$POST_password"
	topic="$POST_topic"
	message="$POST_message"
	send_photo="$POST_send_photo"
	topic_photo="$POST_topic_photo"
	use_ssl="$POST_use_ssl"

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
		tmpfile="$(mktemp -u).json"
                jct $tmpfile set mqtt.host "$host"
                jct $tmpfile set mqtt.port "$port"
                jct $tmpfile set mqtt.username "$username"
                jct $tmpfile set mqtt.password "$password"
                jct $tmpfile set mqtt.client_id "$client_id"
                jct $tmpfile set mqtt.topic "$topic"
                jct $tmpfile set mqtt.message "$message"
                jct $tmpfile set mqtt.topic_photo "$topic_photo"
                jct $tmpfile set mqtt.use_ssl "$use_ssl"
                jct $tmpfile set mqtt.send_photo "$send_photo"
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
<% field_switch "send_photo" "Send a snapshot" %>
<% field_text "topic_photo" "MQTT topic to send the snapshot to" %>
</div>
</div>
<% button_submit %>
</form>

<button type="button" class="btn btn-dark border mb-2" title="Send to MQTT" data-sendto="mqtt">Test</button>

<div class="alert alert-dark ui-debug d-none">
<h4 class="mb-3">Debug info</h4>
<% ex "jct /etc/send2.json get mqtt" %>
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
