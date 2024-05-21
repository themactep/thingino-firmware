#!/usr/bin/haserl
<%in p/common.cgi %>
<%
plugin="ssh"
plugin_name="Send to SSH"
page_title="Send to SSH"
params="enabled host username file path port template cmd"

tmp_file=/tmp/${plugin}.conf

config_file="${ui_config_dir}/${plugin}.conf"
[ ! -f "$config_file" ] && touch $config_file

if [ "POST" = "$REQUEST_METHOD" ]; then
	# parse values from parameters
	for p in $params; do
		eval ${plugin}_${p}=\$POST_${plugin}_${p}
		sanitize "${plugin}_${p}"
	done; unset p

	### Validation
	if [ "true" = "$ssh_enabled" ]; then
		[ "true" = "$ssh_send2ssh" ] && [ -z "$ssh_sshhost" ] && set_error_flag "SSH address cannot be empty."
	fi

	if [ -z "$error" ]; then
		# create temp config file
		:>$tmp_file
		for p in $params; do
			echo "${plugin}_${p}=\"$(eval echo \$${plugin}_${p})\"" >>$tmp_file
		done; unset p
		mv $tmp_file $config_file

		update_caminfo
		redirect_back "success" "${plugin_name} config updated."
	fi

	redirect_to $SCRIPT_NAME
else
	include $config_file

	# Default values
	[ -z "$ssh_port" ] && ssh_port="22"
fi
%>
<%in p/header.cgi %>

<form action="<%= $SCRIPT_NAME %>" method="post">
<% field_switch "ssh_enabled" "Enable sending to SSH server" %>
<div class="row row-cols-1 row-cols-md-2 row-cols-lg-3 g-4 mb-4">
<div class="col">
<% field_text "ssh_host" "SSH host" %>
<% field_text "ssh_port" "SSH port" %>
<% field_text "ssh_username" "SSH username" %>
<% field_text "ssh_file" "SSH src file" %>
</div>
<div class="col">
<% field_text "ssh_path" "SSH path" "relative to SSH root directory" %>
<% field_text "ssh_template" "File template" "Supports <a href=\"https://man7.org/linux/man-pages/man3/strftime.3.html \" target=\"_blank\">strftime()</a> format." %>
<% field_text "ssh_cmd" "SSH command" %>
</div>
<div class="col">
<% ex "cat $config_file" %>
<% button_webui_log %>
</div>
</div>
<% button_submit %>
</form>

<%in p/footer.cgi %>
