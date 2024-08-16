#!/usr/bin/haserl
<%in _common.cgi %>
<%
plugin="development"
page_title="Development"
params="enabled nfs_ip nfs_share"

read_from_env $plugin
[ -z "$development_nfs_share" ] && development_nfs_share="/srv/nfs/www"

if [ "POST" = "$REQUEST_METHOD" ]; then
	for p in $params; do
		eval ${plugin}_${p}=\$POST_${plugin}_${p}
		sanitize "${plugin}_${p}"
	done; unset p

	[ -z "$development_nfs_ip" ] && set_error_flag "NFS server IP cannot be empty."
	[ -z "$development_nfs_share" ] && set_error_flag "NFS share cannot be empty."

	if [ -z "$error" ]; then
		tmpfile=$(mktemp)
		for p in $params; do
			eval "echo ${plugin}_${p}=\$${plugin}_${p}" >> $tmpfile
		done; unset p
		fw_setenv -s $tmpfile
		update_caminfo
		redirect_to "reboot.cgi"
	fi
fi
%>
<%in _header.cgi %>

<div class="row row-cols-1 row-cols-md-2 row-cols-lg-3 g-4 mb-4">
<div class="col">
<form action="<%= $SCRIPT_NAME %>" method="post">
<% field_hidden "action" "update" %>
<% field_switch "development_enabled" "Enable development mode" %>
<% field_text "development_nfs_ip" "NFS server IP" %>
<% field_text "development_nfs_share" "NFS share" %>
<% button_submit %>
</form>
</div>
<div class="col">
</div>
<div class="col">
<% ex "fw_printenv | grep ^development_" %>
</div>
</div>

<%in _footer.cgi %>
