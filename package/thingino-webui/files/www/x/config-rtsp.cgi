#!/bin/haserl
<%in _common.cgi %>
<%
page_title="RTSP/ONVIF Access"

domain="server"
config_file="/etc/onvif.json"
temp_config_file="/tmp/onvif.json"

prudynt_config_file=/etc/prudynt.json

defaults() {
	default_for username "thingino"
	default_for password "thingino"
	default_for onvif_port "80"
	default_for rtsp_port "554"
	default_for rtsp_ch0 "ch0"
	default_for rtsp_ch1 "ch1"
}

set_value() {
	[ -f "$temp_config_file" ] || echo '{}' > "$temp_config_file"
	jct "$temp_config_file" set "$domain.$1" "$2" >/dev/null 2>&1
}

get_value() {
	jct "$config_file" get "$domain.$1" 2>/dev/null
}

read_config() {
	[ -f "$config_file" ] || return

	username="$(get_value username)"
	password="$(get_value password)"
	onvif_port="$(get_value port)"

	# different config file so no `get_value`
	rtsp_port="$(jct $prudynt_config_file get rtsp.port)"
	rtsp_ch0="$(jct $prudynt_config_file get stream0.rtsp_endpoint)"
	rtsp_ch1="$(jct $prudynt_config_file get stream1.rtsp_endpoint)"
	[ -z "$username" ] && username="$(jct $prudynt_config_file get rtsp.username)"
	[ -z "$password" ] && password="$(jct $prudynt_config_file get rtsp.password)"

	#username=$(awk -F: '/Streaming Service/{print $1}' /etc/passwd)
}

read_config

if [ "POST" = "$REQUEST_METHOD" ]; then
	password=$POST_password
	sanitize $password

	if [ -z "$error" ]; then
#		set_value username "$username"
		set_value password "$password"
		jct "$config_file" import "$temp_config_file"
		rm "$temp_config_file"

		# update password in prudynt config
		jct $prudynt_config_file set rtsp.password "$password" > /dev/null

		# update password in system
		echo "$username:$password" | chpasswd -c sha512

		service restart onvif_discovery >/dev/null
		service restart onvif_notify >/dev/null
		service restart prudynt >/dev/null

		redirect_to $SCRIPT_NAME "success" "Data updated."
	else
		redirect_to $SCRIPT_NAME "danger" "Error: $error"
	fi
fi

defaults
%>
<%in _header.cgi %>

<form action="<%= $SCRIPT_NAME %>" method="post" class="mb-4">
<div class="row">
<div class="col-lg-4">
<% field_text "username" "RTSP/ONVIF Username" %>
<% field_password "password" "RTSP/ONVIF Password" %>
<% button_submit %>
</div>
<div class="col-lg-8">
<div class="alert alert-info">
<dl class="mb-0">
<dt>ONVIF URL</dt>
<dd class="cb">onvif://<%= $username %>:<%= $password %>@<%= $network_address %>:<%= $onvif_port %>/onvif/device_service</dd>
<dt>RTSP Mainstream URL</dt>
<dd class="cb">rtsp://<%= $username %>:<%= $password %>@<%= $network_address %>:<%= $rtsp_port %>/<%= $rtsp_ch0 %></dd>
<dt>RTSP Substream URL</dt>
<dd class="cb">rtsp://<%= $username %>:<%= $password %>@<%= $network_address %>:<%= $rtsp_port %>/<%= $rtsp_ch1 %></dd>
</dl>
</div>
</div>
</div>
</form>

<div class="alert alert-dark ui-debug d-none">
<h4 class="mb-3">Debug info</h4>
<% ex "grep ^thingino /etc/shadow" %>
<% ex "jct $config_file get server.password" %>
<% ex "jct $prudynt_config_file get rtsp.password" %>
</div>

<script>
$('#rtsp_username').readOnly = true;
</script>

<%in _footer.cgi %>
