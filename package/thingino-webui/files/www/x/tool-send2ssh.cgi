#!/bin/haserl
<%in _common.cgi %>
<%
page_title="Send to SSH"
params="host username port command"

config_file="$ui_config_dir/ssh.conf"
include $config_file

if [ "POST" = "$REQUEST_METHOD" ]; then
	read_from_post "ssh" "$params"

	error_if_empty "$ssh_host" "SSH address cannot be empty."

	if [ -z "$error" ]; then
		tmp_file=$(mktemp -u)
		[ -f "$config_file" ] && cp "$config_file" "$tmp_file"
		for p in $params; do
			sed -i -r "/^ssh_$p=/d" "$tmp_file"
			echo "ssh_$p=\"$(eval echo \$ssh_$p)\"" >> "$tmp_file"
		done
		mv $tmp_file $config_file
	fi
	redirect_to $SCRIPT_NAME
fi

default_for ssh_port "22"
default_for ssh_username "root"
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
<% ex "cat $config_file" %>
</div>

<%in _footer.cgi %>
