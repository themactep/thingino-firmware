#!/bin/haserl
<%in _common.cgi %>
<%
page_title="Remote Logging"

defaults() {
	default_for rsyslog_port "514"
	default_for rsyslog_local "false"
}

if [ "POST" = "$REQUEST_METHOD" ]; then
	error=""

	read_from_post "rsyslog" "host port local"

	defaults

	if [ -z "$error" ]; then
		save2config "
rsyslog_host=\"$rsyslog_host\"
rsyslog_port=\"$rsyslog_port\"
rsyslog_local=\"$rsyslog_local\"
"
		redirect_to $SCRIPT_NAME "success" "Data updated."
	else
		redirect_to $SCRIPT_NAME "danger" "Error: $error"
	fi
fi

defaults
%>
<%in _header.cgi %>

<div class="row row-cols-1 row-cols-lg-3">
<div class="col">
<form action="<%= $SCRIPT_NAME %>" method="post" class="mb-4">
<div class="row g-1">
<div class="col-10"><% field_text "rsyslog_host" "Syslog server FQDN or IP address" %></div>
<div class="col-2"><% field_text "rsyslog_port" "Port" %></div>
</div>
<% field_switch "rsyslog_local" "Enable local logging" %>
<% button_submit %>
</form>
</div>
</div>

<div class="alert alert-dark ui-debug d-none">
<h4 class="mb-3">Debug info</h4>
<% ex "grep ^rsyslog_ $CONFIG_FILE" %>
</div>

<%in _footer.cgi %>
