#!/usr/bin/haserl
<%in p/common.cgi %>
<%
plugin="rtsp"
plugin_name="RTSP/ONVIF Access"
page_title="RTSP/ONVIF Access"

prudynt_config=/etc/prudynt.cfg
onvif_control=/etc/init.d/S96onvif

rtsp_username=$(awk -F: '/Streaming Service/ {print $1}' /etc/passwd)
[ -z "$rtsp_username" ] && rtsp_username=$(awk -F'"' '/username/{print $2}' $prudynt_config)
[ -z "$rtsp_password" ] && rtsp_password=$(awk -F'"' '/password/{print $2}' $prudynt_config)
[ -z "$rtsp_password" ] && rtsp_password="thingino"

if [ "POST" = "$REQUEST_METHOD" ]; then
	rtsp_password=$POST_rtsp_password
	sanitize rtsp_password

	if [ -z "$error" ]; then
		tmpfile=$(mktemp)
		cat $prudynt_config > $tmpfile
		sed -i "/username:/c\\\tusername: \"$rtsp_username\";" $tmpfile
		sed -i "/password:/c\\\tpassword: \"$rtsp_password\";" $tmpfile
		mv $tmpfile $prudynt_config
		echo "$rtsp_username:$rtsp_password" | chpasswd

		if [ -f "$onvif_control" ]; then
			$onvif_control restart >> /tmp/webui.log
		else
			echo "$onvif_control not found" >> /tmp/webui.log
		fi

		update_caminfo
		redirect_to $SCRIPT_NAME
	fi
fi
%>
<%in p/header.cgi %>

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
<%in p/footer.cgi %>
