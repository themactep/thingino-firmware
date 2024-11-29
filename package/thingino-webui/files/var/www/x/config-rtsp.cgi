#!/bin/haserl
<%in _common.cgi %>
<%
page_title="RTSP/ONVIF Access"

prudynt_config=/etc/prudynt.cfg
onvif_config=/etc/onvif.conf
onvif_discovery=/etc/init.d/S96onvif_discovery
onvif_notify=/etc/init.d/S97onvif_notify

rtsp_username=$(awk -F: '/Streaming Service/{print $1}' /etc/passwd)
default_for rtsp_username "$(awk -F'"' '/username/{print $2}' $prudynt_config)"
default_for rtsp_password "$(awk -F'"' '/password/{print $2}' $prudynt_config)"
default_for rtsp_password "thingino"

if [ "POST" = "$REQUEST_METHOD" ]; then
	rtsp_password=$POST_rtsp_password
	sanitize rtsp_password

	if [ -z "$error" ]; then
		tmpfile=$(mktemp)
		cat $onvif_config > $tmpfile
		#sed -i "/^user=/cuser=$rtsp_username" $tmpfile
		sed -i "/^password=/cpassword=$rtsp_password" $tmpfile
		mv $tmpfile $onvif_config

		prudyntcfg set rtsp.password "\"$rtsp_password\""

		echo "$rtsp_username:$rtsp_password" | chpasswd -c sha512

		if [ -f "$onvif_discovery" ]; then
			$onvif_discovery restart >> /tmp/webui.log
		else
			echo "$onvif_discovery not found" >> /tmp/webui.log
		fi

		if [ -f "$onvif_notify" ]; then
			$onvif_notify restart >> /tmp/webui.log
		else
			echo "$onvif_notify not found" >> /tmp/webui.log
		fi

		/etc/init.d/S95prudynt restart >/dev/null
		update_caminfo
		redirect_to $SCRIPT_NAME
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
<dd class="cb">onvif://<%= $rtsp_username %>:<%= $rtsp_password %>@<%= $network_address %>/onvif/device_service</dd>
<dt>RTSP Mainstream URL</dt>
<dd class="cb">rtsp://<%= $rtsp_username %>:<%= $rtsp_password %>@<%= $network_address %>/<%= $rtsp_endpoint_ch0 %></dd>
<dt>RTSP Substream URL</dt>
<dd class="cb">rtsp://<%= $rtsp_username %>:<%= $rtsp_password %>@<%= $network_address %>/<%= $rtsp_endpoint_ch1 %></dd>
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
