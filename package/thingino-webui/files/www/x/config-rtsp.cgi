#!/bin/haserl
<%in _common.cgi %>
<%
page_title="RTSP/ONVIF Access"

prudynt_config=/etc/prudynt.json
onvif_config=/etc/onvif.conf

rtsp_username=$(awk -F: '/Streaming Service/{print $1}' /etc/passwd)
default_for rtsp_username "$(jct $prudynt_config get rtsp.username)"
default_for rtsp_username "thingino"

default_for rtsp_password "$(jct $prudynt_config get rtsp.password)"
default_for rtsp_password "thingino"

rtsp_port=$(jct $prudynt_config get rtsp.port)
default_for rtsp_port "554"

onvif_port=$(awk -F= '/^port=/{print $2}' /etc/onvif.conf)
default_for onvif_port "80"

rtsp_endpoint_ch0=$(jct $prudynt_config get stream0.rtsp_endpoint | tr -d '"')
default_for rtsp_endpoint_ch0 "ch0"

rtsp_endpoint_ch1=$(jct $prudynt_config get stream1.rtsp_endpoint | tr -d '"')
default_for rtsp_endpoint_ch1 "ch1"

if [ "POST" = "$REQUEST_METHOD" ]; then
	rtsp_password=$POST_rtsp_password
	sanitize rtsp_password

	if [ -z "$error" ]; then
		tmpfile=$(mktemp)
		cat $onvif_config > $tmpfile
		#sed -i "/^user=/cuser=$rtsp_username" $tmpfile
		sed -i "/^password=/cpassword=$rtsp_password" $tmpfile
		mv $tmpfile $onvif_config

		jct $prudynt_config set rtsp.password "$rtsp_password"

		echo "$rtsp_username:$rtsp_password" | chpasswd -c sha512

		service restart onvif_discovery >/dev/null
		service restart onvif_notify >/dev/null
		service restart prudynt >/dev/null
		redirect_to $SCRIPT_NAME "success" "Data updated."
	else
		redirect_to $SCRIPT_NAME "danger" "Error: $error"
	fi
fi
%>
<%in _header.cgi %>

<form action="<%= $SCRIPT_NAME %>" method="post" class="mb-4">
<div class="row">
<div class="col-lg-4">
<% field_text "rtsp_username" "RTSP/ONVIF Username" %>
<% field_password "rtsp_password" "RTSP/ONVIF Password" %>
<% button_submit %>
</div>
<div class="col-lg-8">
<div class="alert alert-info">
<dl class="mb-0">
<dt>ONVIF URL</dt>
<dd class="cb">onvif://<%= $rtsp_username %>:<%= $rtsp_password %>@<%= $network_address %>:<%= $onvif_port %>/onvif/device_service</dd>
<dt>RTSP Mainstream URL</dt>
<dd class="cb">rtsp://<%= $rtsp_username %>:<%= $rtsp_password %>@<%= $network_address %>:<%= $rtsp_port %>/<%= $rtsp_endpoint_ch0 %></dd>
<dt>RTSP Substream URL</dt>
<dd class="cb">rtsp://<%= $rtsp_username %>:<%= $rtsp_password %>@<%= $network_address %>:<%= $rtsp_port %>/<%= $rtsp_endpoint_ch1 %></dd>
</dl>
</div>
</div>
</div>
</form>

<div class="alert alert-dark ui-debug d-none">
<h4 class="mb-3">Debug info</h4>
<% ex "grep ^thingino /etc/shadow" %>
<% ex "grep ^password $onvif_config" %>
<% ex "grep password $prudynt_config | sed -E 's/^\s+//'" %>
</div>

<script>
$('#rtsp_username').readOnly = true;
</script>

<%in _footer.cgi %>
