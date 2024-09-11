#!/bin/haserl
<%in _common.cgi %>
<%
plugin="rtsp"
plugin_name="RTSP/ONVIF Access"
page_title="RTSP/ONVIF Access"

prudynt_config=/etc/prudynt.cfg
onvif_config=/etc/onvif.conf
onvif_discovery=/etc/init.d/S96onvif_discovery
onvif_notify=/etc/init.d/S97onvif_notify

rtsp_username=$(awk -F: '/Streaming Service/ {print $1}' /etc/passwd)
[ -z "$rtsp_username" ] && rtsp_username=$(awk -F'"' '/username/{print $2}' $prudynt_config)
[ -z "$rtsp_password" ] && rtsp_password=$(awk -F'"' '/password/{print $2}' $prudynt_config)
[ -z "$rtsp_password" ] && rtsp_password="thingino"

if [ "POST" = "$REQUEST_METHOD" ]; then
	rtsp_password=$POST_rtsp_password
	sanitize rtsp_password

	if [ -z "$error" ]; then
		# change password for onvif server
		tmpfile=$(mktemp)
		cat $onvif_config > $tmpfile
		#sed -i "/^user=/cuser=$rtsp_username" $tmpfile
		sed -i "/^password=/cpassword=$rtsp_password" $tmpfile
		mv $tmpfile $onvif_config

		# change password for prudynt streamer
		tmpfile=$(mktemp)
		cat $prudynt_config > $tmpfile
		#prudyntcfg set rtsp username \"$rtsp_username\"
		prudyntcfg set rtsp password \"$rtsp_password\"
		mv $tmpfile $prudynt_config

		# change password for system user
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

		update_caminfo
		redirect_to $SCRIPT_NAME
	fi
fi
%>
<%in _header.cgi %>

<div class="row g-4 mb-4">
<div class="col col-12 col-xl-4">
<form action="<%= $SCRIPT_NAME %>" method="post">
<% field_text "rtsp_username" "RTSP/ONVIF Username" %>
<% field_password "rtsp_password" "RTSP/ONVIF Password" %>
<% button_submit %>
</form>
</div>
<div class="col col-12 col-xl-8">
<pre class="mt-4">
rtsp://<%= $rtsp_username %>:<%= $rtsp_password %>@<%= $network_address %>/ch0
rtsp://<%= $rtsp_username %>:<%= $rtsp_password %>@<%= $network_address %>/ch1
onvif://<%= $rtsp_username %>:<%= $rtsp_password %>@<%= $network_address %>/onvif/device_service
</pre>
</div>
</div>

<script>
$('#rtsp_username').readOnly = true;
</script>
<%in _footer.cgi %>
