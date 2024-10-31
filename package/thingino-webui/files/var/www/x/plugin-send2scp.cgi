#!/bin/haserl
<%in _common.cgi %>
<%
plugin="scp"
plugin_name="Send via scp"
page_title="Send via scp"
params="enabled host port user path template command"

SCP_KEY="/root/.ssh/id_dropbear"

config_file="$ui_config_dir/$plugin.conf"
include $config_file

if [ "POST" = "$REQUEST_METHOD" ]; then
	# parse values from parameters
	read_from_post "$plugin" "$params"

	# validate
	[ "true" = "$scp_enabled" ] && [ -z "$scp_host" ] && set_error_flag "Target host address cannot be empty."
	[ -z "$scp_template" ] && scp_template="$network_hostname-%Y%m%d-%H%M%S.jpg"
	[ -f $SCP_KEY ] || dropbearkey -t ed25519 -f $SCP_KEY

	if [ -z "$error" ]; then
		tmpfile=$(mktemp)
		for p in $params; do
			echo "${plugin}_$p=\"$(eval echo \$${plugin}_$p)\"" >>$tmpfile
		done; unset p
		mv $tmpfile $config_file

		update_caminfo
		redirect_back "success" "$plugin_name config updated."
	fi

	redirect_to $SCRIPT_NAME
else
	# Default values
	[ -z "$scp_port" ] && scp_port="22"
	[ -z "$scp_user" ] && scp_user="root"
	[ -z "$scp_template" ] && scp_template="$network_hostname-%Y%m%d-%H%M%S.jpg"
fi
%>
<%in _header.cgi %>

<form action="<%= $SCRIPT_NAME %>" method="post">
<% field_switch "scp_enabled" "Enable sending to the remote host via scp" %>
<div class="row row-cols-1 row-cols-md-2 row-cols-lg-3 g-4 mb-4">
<div class="col">
<% field_text "scp_host" "Remote machine address" %>
<% field_text "scp_port" "Remote machine port" %>
<% field_text "scp_user" "Remote machine username" %>
<% field_text "scp_path" "Path on the remote machine" "Omit the leading slash for path relative to user's home" %>
<% field_text "scp_template" "Filename template" "$STR_SUPPORTS_STRFTIME" %>
<% field_text "scp_command" "Follow-up command to run remotely" %>
</div>
<div class="col">
<% ex "xxd -c 8 $SCP_KEY" %>
</div>
<div class="col">
<% ex "cat $config_file" %>
</div>
</div>
<% button_submit %>
</form>

<%in _footer.cgi %>
