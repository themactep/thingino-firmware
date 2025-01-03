#!/bin/haserl
<%in _common.cgi %>
<%
page_title="SSH Host key"

key_file="/etc/dropbear/dropbear_ed25519_host_key"
envname="sshkey_ed25519"
backup=$(fw_printenv -n $envname)
keyb64=$(base64 < $key_file | tr -d '\n')

case "$POST_action" in
	backup)
		if [ -z "$backup" ]; then
			fw_setenv $envname $keyb64
			redirect_back
		fi
		set_error_flag "The key is already in the backup. You must delete it before saving a new key."
		;;
	restore)
		if [ -n "$backup" ]; then
			echo $backup | base64 -d > $key_file
			redirect_back
		fi
		set_error_flag "The key is not in the backup."
		;;
	delete)
		if [ -n "$backup" ]; then
			fw_setenv $envname
			redirect_back
		fi
		set_error_flag "The key is not in the backup."
		;;
esac
%>
<%in _header.cgi %>

<div class="row row-cols-1 row-cols-lg-3 g-4 mb-4">
<div class="col">
<h3>Backup</h3>
<form action="<%= $SCRIPT_NAME %>" method="post">
<% field_hidden "action" "backup" %>
<p>Back up your existing SSH host key in the firmware environment to restore it later after the overlay wipe.</p>
<% button_submit "Back up SSH Host key" "danger" %>
</form>
</div>
<div class="col">
<h3>Restore</h3>
<p>Restore the previously saved SSH host key from backup allows you to maintain the existing client authentication.</p>
<form action="<%= $SCRIPT_NAME %>" method="post">
<% field_hidden "action" "restore" %>
<% button_submit "Restore SSH Host key from backup" "danger" %>
</form>
</div>
<div class="col">
<h3>Delete</h3>
<p>You can delete the stored SSH host key from the backup, for example, to replace it with a new version of the key.</p>
<form action="<%= $SCRIPT_NAME %>" method="post">
<% field_hidden "action" "delete" %>
<% button_submit "Delete SSH Host key backup" "danger" %>
</form>
</div>
</div>

<div class="alert alert-dark ui-debug d-none">
<h4 class="mb-3">Debug info</h4>
<% ex "fw_printenv -n $envname" %>
<h5>Key on disk</h5>
<% ex "base64 < $key_file | tr -d '\n'" %>
</div>

<%in _footer.cgi %>
