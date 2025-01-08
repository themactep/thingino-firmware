#!/bin/haserl
<%in _common.cgi %>
<%
plugin="email"
plugin_name="Send to email"
page_title="Send to email"
params="enabled attach_snapshot attach_video from_name from_address insecure_ssl to_name to_address subject body smtp_host smtp_port smtp_username smtp_password smtp_use_ssl"

config_file="$ui_config_dir/email.conf"
include $config_file

if [ "POST" = "$REQUEST_METHOD" ]; then
	read_from_post "email" "$params"

	# normalize
	email_body="$(echo "$email_body" | tr "\r?\n" " ")"

	if [ "true" = "$email_enabled" ]; then
		error_if_empty "$email_smtp_host" "SMTP host cannot be empty."
		error_if_empty "$email_from_address" "Sender email address cannot be empty."
		error_if_empty "$email_from_name" "Sender name cannot be empty."
		error_if_empty "$email_to_address" "Recipient email address cannot be empty."
		error_if_empty "$email_to_name" "Recipient name cannot be empty."
	fi

	if [ -z "$error" ]; then
		tmp_file=$(mktemp)
		for p in $params; do
			echo "email_$p=\"$(eval echo \$email_$p)\"" >>$tmp_file
		done; unset p
		mv $tmp_file $config_file

		update_caminfo
		redirect_back "success" "$plugin_name config updated."
	fi

	redirect_to $SCRIPT_NAME
else
	# Default values
	default_for email_insecure_ssl false
	default_for email_attach_snapshot false
	default_for email_attach_video true
	default_for email_smtp_port 25
	default_for email_from_name "Camera $network_hostname"
	default_for email_to_name "Camera admin"
	#[ -z "$email_subject" ] && email_subject="Snapshot from $network_hostname"
fi
%>
<%in _header.cgi %>

<form action="<%= $SCRIPT_NAME %>" method="post" class="mb-4">

<% field_switch "email_enabled" "Enable sending to email address" %>
<div class="row row-cols-1 row-cols-md-2 row-cols-xl-3 g-4 mb-4">
<div class="col">
<div class="row g-1">
<div class="col-10"><% field_text "email_smtp_host" "SMTP server FQDN or IP address" %></div>
<div class="col-2"><% field_text "email_smtp_port" "Port" %></div>
</div>
<% field_text "email_smtp_username" "SMTP username" %>
<% field_password "email_smtp_password" "SMTP password" %>
<% field_switch "email_smtp_use_ssl" "Use TLS/SSL" %>
<% field_switch "email_insecure_ssl" "Ignore SSL certificate validity" %>
</div>
<div class="col">
<% field_text "email_from_name" "Sender's name" %>
<% field_text "email_from_address" "Sender's address" %>
<% field_text "email_to_name" "Recipient's name" %>
<% field_text "email_to_address" "Recipient's address" %>
</div>
<div class="col">
<% field_text "email_subject" "Email subject" %>
<% field_textarea "email_body" "Email text" "Line breaks will be replaced with whitespaces." %>

<p class="label">Attachment</p>
<div class="btn-group" role="group" aria-label="Send attachment">
<input type="radio" class="btn-check" name="email_attach" id="email_attach_nothing" autocomplete="off">
<label class="btn btn-outline-primary" for="email_attach_nothing">Nothing</label>
<input type="radio" class="btn-check" name="email_attach" id="email_attach_snapshot" autocomplete="off">
<label class="btn btn-outline-primary" for="email_attach_snapshot">Snapshot</label>
<input type="radio" class="btn-check" name="email_attach" id="email_attach_video" autocomplete="off">
<label class="btn btn-outline-primary" for="email_attach_video">Video</label>
</div>

<% # field_switch "email_attach_snapshot" "Attach snapshot" %>
<% # field_switch "email_attach_video" "Attach video" %>
</div>
</div>
<% button_submit %>
</form>

<p>Use a real email address where bounce reports can be sent to.</p>

<script>
$('#email_body').style.height = "6rem";
$('#email_smtp_use_ssl').addEventListener('change', ev => {
	const el=$('#email_smtp_port');
	if (ev.target.checked) {
		if (el.value === "25") el.value="465";
	} else {
		if (el.value === "465") el.value="25";
	}
});
</script>

<%in _footer.cgi %>
