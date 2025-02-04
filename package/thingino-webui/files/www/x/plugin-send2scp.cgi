#!/bin/haserl
<%in _common.cgi %>
<%
plugin="scp"
plugin_name="Send via scp"
page_title="Send via scp"
params="host port user path template command"

SCP_KEY="/root/.ssh/id_dropbear"
[ -f $SCP_KEY ] || dropbearkey -t ed25519 -f $SCP_KEY

config_file="$ui_config_dir/scp.conf"
include $config_file

if [ "POST" = "$REQUEST_METHOD" ]; then
	read_from_post "scp" "$params"

	error_if_empty "$scp_host" "Target host address cannot be empty."

	default_for scp_template "$network_hostname-%Y%m%d-%H%M%S.jpg"

	if [ -z "$error" ]; then
		tmp_file=$(mktemp -u)
		[ -f "$config_file" ] && cp "$config_file" "$tmp_file"
		for p in $params; do
			sed -i -r "/^scp_$p=/d" "$tmp_file"
			echo "scp_$p=\"$(eval echo \$scp_$p)\"" >> "$tmp_file"
		done
		mv $tmp_file $config_file
	fi
	redirect_to $SCRIPT_NAME
fi

default_for scp_port "22"
default_for scp_user "root"
default_for scp_template "$network_hostname-%Y%m%d-%H%M%S.jpg"
%>
<%in _header.cgi %>

<form action="<%= $SCRIPT_NAME %>" method="post" class="mb-4">
<div class="row row-cols-1 row-cols-md-2 row-cols-lg-3">
<div class="col">
<div class="row g-1">
<div class="col-10"><% field_text "scp_host" "Remote machine FQDN or IP address" %></div>
<div class="col-2"><% field_text "scp_port" "port" %></div>
</div>
<% field_text "scp_user" "Remote machine username" %>
</div>
<div class="col">
<% field_text "scp_path" "Path on the remote machine" "Omit the leading slash for path relative to user's home" %>
<% field_text "scp_template" "Filename template" "$STR_SUPPORTS_STRFTIME" %>
</div>
<div class="col">
<% field_text "scp_command" "Follow-up command to run remotely" %>
</div>
</div>
<% button_submit %>
</form>

<div class="alert alert-dark ui-debug d-none">
<h4 class="mb-3">Debug info</h4>
<% ex "cat $config_file" %>
<% ex "xxd $SCP_KEY" %>
</div>

<%in _footer.cgi %>
