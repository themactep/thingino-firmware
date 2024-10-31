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
	# parse values from parameters
	read_from_post "$plugin" "$params"

	# validate
	[ "true" = "$ssh_enabled" ] && [ -z "$ssh_host" ] && \
		set_error_flag "SSH address cannot be empty."

	if [ -z "$error" ]; then
		tmp_file=$(mktemp)
		for p in $params; do
			echo "${plugin}_$p=\"$(eval echo \$${plugin}_$p)\"" >>$tmp_file
		done; unset p
		mv $tmp_file $config_file

		update_caminfo
		redirect_back "success" "$plugin_name config updated."
	fi

	redirect_to $SCRIPT_NAME
else
	# Default values
	[ -z "$ssh_port" ] && ssh_port="22"
	[ -z "$ssh_username" ] && ssh_username="root"
fi
%>
<%in _header.cgi %>

<form action="<%= $SCRIPT_NAME %>" method="post">
<% field_switch "ssh_enabled" "Enable sending to SSH server" %>
<div class="row row-cols-1 row-cols-md-2 row-cols-lg-3 g-4 mb-4">
<div class="col">
<% field_text "ssh_host" "SSH host" %>
<% field_text "ssh_port" "SSH port" %>
<% field_text "ssh_username" "SSH username" %>
<% field_text "ssh_command" "Remote command" "$STR_SUPPORTS_STRFTIME" %>
</div>
<div class="col">
</div>
<div class="col">
<% ex "cat $config_file" %>
</div>
</div>
<% button_submit %>
</form>

<%in _footer.cgi %>
