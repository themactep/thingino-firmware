#!/bin/haserl
<%in _common.cgi %>
<%
plugin="ssh"
plugin_name="Send to SSH"
page_title="Send to SSH"
params="enabled host username port command"

config_file="$ui_config_dir/$plugin.conf"
include $config_file

if [ "POST" = "$REQUEST_METHOD" ]; then
	read_from_post "$plugin" "$params"

	if [ "true" = "$ssh_enabled" ]; then
		error_if_empty "$ssh_host" "SSH address cannot be empty."
	fi

	if [ -z "$error" ]; then
		tmpfile=$(mktemp -u)
		for p in $params; do
			echo "${plugin}_$p=\"$(eval echo \$${plugin}_$p)\"" >>$tmpfile
		done; unset p
		mv $tmpfile $config_file

		update_caminfo
		redirect_back "success" "$plugin_name config updated."
	fi
fi

default_for ssh_port "22"
default_for ssh_username "root"
%>
<%in _header.cgi %>

<form action="<%= $SCRIPT_NAME %>" method="post" class="mb-4">
<% field_switch "ssh_enabled" "Enable sending to SSH server" %>
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
<% ex "cat $config_file" %>
</div>

<%in _footer.cgi %>
