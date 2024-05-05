#!/usr/bin/haserl
<%in p/common.cgi %>
<%
plugin="vtun"
plugin_name="Virtual Tunnel"
page_title="Virtual tunnel"
service_file=/etc/init.d/S98vtun
conf_file=/tmp/vtund.conf

if [ -n "$POST_action" ] && [ "$POST_action" = "reset" ]; then
	killall tunnel
	killall vtund
	rm $conf_file
	rm $service_file
	redirect_to "$SCRIPT_NAME" "danger" "Tunnel is down"
fi

if [ -n "$POST_vtun_host" ]; then
	echo -e "#!/bin/sh\n\ntunnel $POST_vtun_host\n" >$service_file
	chmod +x $service_file
	$service_file
	redirect_to "$SCRIPT_NAME" "success" "Tunnel is up"
fi
%>
<%in p/header.cgi %>

<div class="row g-4 mb-4">
<div class="col col-lg-4">
<% if [ -f "$conf_file" ]; then %>
<div class="alert alert-success">
<h4>Virtual Tunnel is up</h4>
<p>Use the following credentials to set up remote access via active virtual tunnel:</p>
<dl class="mb-0">
<dt>Tunnel ID</dt>
<dd><%= ${network_macaddr//:/} | tr a-z A-Z %></dd>
<dt>Password</dt>
<dd><% grep password $conf_file | xargs | cut -d' ' -f2 | sed 's/;$//' %>
</dl>
</div>
<% fi %>

<h3>Settings</h3>
<form action="<%= $SCRIPT_NAME %>" method="post">
<% if [ -f "$service_file" ]; then %>
<% field_hidden "action" "reset" %>
<% button_submit "Reset configuration" %>
<% else %>
<% field_text "vtun_host" "Virtual Tunnel host" "Your Virtual Tunnel server address." %>
<% button_submit %>
<% fi %>
</form>
</div>
<div class="col col-lg-8">
<h3>Configuration</h3>
<%
[ -f "$service_file" ] && ex "cat $service_file"
[ -f "$conf_file" ] && ex "cat $conf_file"
ex "ps | grep tunnel"
ex "ps | grep vtund"
%>
</div>
</div>

<%in p/footer.cgi %>
