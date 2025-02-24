#!/bin/haserl
<%in _common.cgi %>
<%
page_title="Send to SSH"

defaults() {
	default_for ssh_port "22"
	default_for ssh_username "root"
}

if [ "POST" = "$REQUEST_METHOD" ]; then
	error=""

	read_from_post "ssh" "host username port command"

	error_if_empty "$ssh_host" "SSH address cannot be empty."

	defaults

	if [ -z "$error" ]; then
		save2config "
ssh_host=\"$ssh_host
ssh_port=\"$ssh_port\"
ssh_username=\"$ssh_username\"
ssh_command=\"$ssh_command\"
"
	fi
	redirect_to $SCRIPT_NAME
fi

defaults
%>
<%in _header.cgi %>

<form action="<%= $SCRIPT_NAME %>" method="post" class="mb-4">
<div class="row row-cols-1 row-cols-md-2 row-cols-lg-3">
<div class="col">
<div class="row g-1">
<div class="col-10"><% field_text "ssh_host" "Remote machine FQDN or IP address" %></div>
<div class="col-2"><% field_text "ssh_port" "port" %></div>
</div>
<% field_text "ssh_username" "Remote machine username" %>
<% field_text "ssh_command" "Remote command" "$STR_SUPPORTS_STRFTIME" %>
</div>
</div>
<% button_submit %>
</form>

<div class="alert alert-dark ui-debug d-none">
<h4 class="mb-3">Debug info</h4>
<% ex "grep ^ssh_ $WEB_CONFIG_FILE" %>
</div>

<%in _footer.cgi %>
