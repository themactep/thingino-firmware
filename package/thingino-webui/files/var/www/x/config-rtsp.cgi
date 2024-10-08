#!/bin/haserl
<%in _common.cgi %>
<%
page_title="RTSP/ONVIF Access"

rtsp_username=$(awk -F: '/Streaming Service/{print $1}' /etc/passwd)
[ -z "$rtsp_username" ] && rtsp_username=$(awk -F'"' '/username/{print $2}' $prudynt_config)
[ -z "$rtsp_password" ] && rtsp_password=$(awk -F'"' '/password/{print $2}' $prudynt_config)
[ -z "$rtsp_password" ] && rtsp_password="thingino"
%>
<%in _header.cgi %>

<div class="row row-cols-1 row-cols-lg-3 g-4 mb-4">
	<div class="col">
		<h3>RTSP/ONVIF Access</h3>
		<form action="<%= $SCRIPT_NAME %>" method="post">
		<% field_text "rtsp_username" "RTSP/ONVIF Username" %>
		<% field_password "rtsp_password" "RTSP/ONVIF Password" %>
		<% button_submit %>
		</form>
	</div>
</div>

<pre class="mt-4">
onvif://<%= $rtsp_username %>:<%= $rtsp_password %>@<%= $network_address %>/onvif/device_service
</pre>

<script>
$('#rtsp_username').readOnly = true;
</script>

<%in _footer.cgi %>
