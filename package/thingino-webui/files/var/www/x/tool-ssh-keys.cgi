#!/bin/haserl
<%in _common.cgi %>
<%
page_title="SSH key"

function readKey() {
	if [ -n "$(get sshkey_${1})" ]; then
		alert "$(get sshkey_${1})" "secondary" "style=\"overflow-wrap: anywhere;\""
	fi
}

function saveKey() {
	if [ -n "$(get sshkey_${1})" ]; then
		alert_save "danger" "${1} key already in backup. You need to delete it before saving a new key."
	else
		fw_setenv sshkey_${1} $(gzip -c /etc/dropbear/dropbear_${1}_host_key - 2>/dev/null | base64 | tr -d '\n')
	fi
}

function restoreKey() {
	if [ -z "$(get sshkey_${1})" ]; then
		alert_save "danger" "${1} key is not in the environment."
	else
		get sshkey_${1} | base64 -d | gzip -d > /etc/dropbear/dropbear_${1}_host_key
		alert_save "success" "${1} key restored from environment."
	fi
}

function deleteKey() {
	if [ -z "$(get sshkey_${1})" ]; then
		alert_save "danger" "${1} Cannot find saved SSH key."
	else
		fw_setenv sshkey_${1}
		alert_save "success" "${1} key deleted from environment."
	fi
}

case "$POST_action" in
	backup)
		saveKey "ed25519"
		redirect_back
		;;
	restore)
		restoreKey "ed25519"
		redirect_back
		;;
	delete)
		deleteKey "ed25519"
		redirect_back
		;;
	*)
%>
<%in _header.cgi %>

<div class="row row-cols-1 row-cols-md-2 row-cols-lg-3 g-4 mb-4">
<div class="col">
<h3>Key Backup</h3>
<form action="<%= $SCRIPT_NAME %>" method="post">
<% field_hidden "action" "backup" %>
<p>You can back up your existing SSH key into firmware environment and restore them later, after overlay wiping.</p>
<% button_submit "Backup SSH key" "danger" %>
</form>
</div>
<div class="col">
<h3>Key Restore</h3>
<p>Restoring previously saved SSH key from firmware environment will let you keep exsiting client's authentication.</p>
<form action="<%= $SCRIPT_NAME %>" method="post">
<% field_hidden "action" "restore" %>
<% button_submit "Restore SSH key from backup" "danger" %>
</form>
</div>
<div class="col">
<h3>Key Delete</h3>
<p>You can delete saved key from firmware environment, e.g. to replace them with a new key.</p>
<form action="<%= $SCRIPT_NAME %>" method="post">
<% field_hidden "action" "delete" %>
<% button_submit "Delete SSH key backup." "danger" %>
</form>
</div>
</div>

<% readKey "ed25519" %>

<%in _footer.cgi %>
<% esac %>
