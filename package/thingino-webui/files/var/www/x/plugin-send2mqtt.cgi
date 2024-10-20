#!/bin/haserl
<%in _common.cgi %>
<%
plugin="mqtt"
plugin_name="MQTT client"
page_title="MQTT client"
params="enabled host port client_id username password topic message send_snap snap_topic use_ssl"

[ -f /usr/bin/mosquitto_pub ] || redirect_to "/" "danger" "MQTT client is not a part of your firmware."

config_file="$ui_config_dir/$plugin.conf"
[ -f "$config_file" ] || touch $config_file

if [ "POST" = "$REQUEST_METHOD" ]; then
	# parse values from parameters
	for p in $params; do
		eval ${plugin}_$p=\$POST_${plugin}_$p
		sanitize "${plugin}_$p"
	done; unset p

	# validate
	if [ "true" = "$mqtt_enabled" ]; then
		[ -z "$mqtt_host" ] && set_error_flag "MQTT broker host cannot be empty."
		[ -z "$mqtt_port" ] && set_error_flag "MQTT port cannot be empty."
		# [ -z "$mqtt_username" ] && set_error_flag "MQTT username cannot be empty."
		# [ -z "$mqtt_password" ] && set_error_flag "MQTT password cannot be empty."
		[ -z "$mqtt_topic" ] && alert_append "danger" "MQTT topic cannot be empty."
		[ -z "$mqtt_message" ] && alert_append "danger" "MQTT message cannot be empty."
	fi

	if [ "${mqtt_topic:0:1}" = "/" ] || [ "${mqtt_snap_topic:0:1}" = "/" ]; then
		set_error_flag "MQTT topic should not start with a slash."
	fi

	if [ "$mqtt_topic" != "${mqtt_topic// /}" ] || [ "$mqtt_snap_topic" != "${mqtt_snap_topic// /}" ]; then
		set_error_flag "MQTT topic should not contain spaces."
	fi

	if [ -n "$(echo $mqtt_topic | sed -r -n /[^a-zA-Z0-9/]/p)" ] || [ -n "$(echo $mqtt_snap_topic | sed -r -n /[^a-zA-Z0-9/]/p)" ]; then
		set_error_flag "MQTT topic should not include non-ASCII characters."
	fi

	if [ "true" = "$mqtt_send_snap" ] && [ -z "$mqtt_snap_topic" ]; then
		set_error_flag "MQTT topic for snapshot should not be empty."
	fi

	if [ -z "$error" ]; then
		tmp_file=$(mktemp)
		for p in $params; do
			echo "${plugin}_$p=\"$(eval echo \$${plugin}_$p)\"" >>$tmp_file
		done; unset p
		mv $tmp_file $config_file

		update_caminfo
		redirect_back "success" "$plugin_name config updated."
	fi

	redirect_to $SCRIPT_NAME
else
	include $config_file

	# Default values
	[ -z "$mqtt_client_id" ] && mqtt_client_id="${network_macaddr//:/}"
	[ -z "$mqtt_port" ] && mqtt_port="1883"
	[ -z "$mqtt_topic" ] && mqtt_topic="thingino/$mqtt_client_id"
	[ -z "$mqtt_message" ] && mqtt_message=""
fi
%>
<%in _header.cgi %>

<form action="<%= $SCRIPT_NAME %>" method="post">
<% field_switch "mqtt_enabled" "Enable MQTT client" %>
<div class="row row-cols-1 row-cols-md-2 row-cols-lg-3 g-4 mb-4">
<div class="col">
<% field_text "mqtt_host" "MQTT broker host" %>
<% field_switch "mqtt_use_ssl" "Use SSL" %>
<% field_text "mqtt_port" "MQTT broker port" %>
<% field_text "mqtt_client_id" "MQTT client ID" %>
<% field_text "mqtt_username" "MQTT broker username" %>
<% field_password "mqtt_password" "MQTT broker password" %>
</div>
<div class="col">
<% field_text "mqtt_topic" "MQTT topic" %>
<% field_textarea "mqtt_message" "MQTT message" "$STR_SUPPORTS_STRFTIME" %>
<% field_switch "mqtt_send_snap" "Send a snapshot" %>
<% field_text "mqtt_snap_topic" "MQTT topic to send the snapshot to" %>
<% field_switch "mqtt_socks5_enabled" "Use SOCKS5" "$STR_CONFIGURE_SOCKS" %>
</div>
<div class="col">
<% ex "cat $config_file" %>
</div>
</div>
<% button_submit %>
</form>

<script>
$('#mqtt_message').style.height = '7rem';
$('#mqtt_use_ssl').addEventListener('change', ev => {
	const el=$('#mqtt_port');
	if (ev.target.checked) {
		if (el.value === '1883') el.value='8883';
	} else {
		if (el.value === '8883') el.value='1883';
	}
});
</script>

<%in _footer.cgi %>
