#!/bin/haserl
<%in _common.cgi %>
<%
plugin="email"
plugin_name="Send to email"
page_title="Send to email"
params="enabled attach_snapshot from_name from_address to_name to_address subject body smtp_host smtp_port smtp_username smtp_password smtp_use_ssl socks5_enabled"

config_file="${ui_config_dir}/${plugin}.conf"
[ ! -f "$config_file" ] && touch $config_file

if [ "POST" = "$REQUEST_METHOD" ]; then
	# parse values from parameters
	for p in $params; do
		eval ${plugin}_${p}=\$POST_${plugin}_${p}
		sanitize "${plugin}_${p}"
	done; unset p

	# normalize
	email_body="$(echo "$email_body" | tr "\r?\n" " ")"

	# validate
	if [ "true" = "$email_enabled" ]; then
		[ -z "$email_smtp_host"    ] && set_error_flag "SMTP host cannot be empty."
		[ -z "$email_from_address" ] && set_error_flag "Sender email address cannot be empty."
		[ -z "$email_from_name"    ] && set_error_flag "Sender name cannot be empty."
		[ -z "$email_to_address"   ] && set_error_flag "Recipient email address cannot be empty."
		[ -z "$email_to_name"      ] && set_error_flag "Recipient name cannot be empty."
	fi

	if [ -z "$error" ]; then
		tmp_file=$(mktemp)
		for p in $params; do
			echo "${plugin}_${p}=\"$(eval echo \$${plugin}_${p})\"" >>$tmp_file
		done; unset p
		mv $tmp_file $config_file

		update_caminfo
		redirect_back "success" "$plugin_name config updated."
	fi

	redirect_to $SCRIPT_NAME
else
	include $config_file

	# Default values
	[ -z "$email_attach_snapshot" ] && email_attach_snapshot="true"
	[ -z "$email_smtp_port" ] && email_smtp_port="25"
	[ -z "$email_from_name" ] && email_from_name="Camera ${network_hostname}"
	[ -z "$email_to_name" ] && email_to_name="Camera admin"
	#  [ -z "$email_subject" ] && email_subject="Snapshot from ${network_hostname}"
fi
%>
<%in _header.cgi %>

<form action="<%= $SCRIPT_NAME %>" method="post">
<% field_switch "email_enabled" "Enable sending to email" %>
<div class="row row-cols-1 row-cols-md-2 row-cols-lg-3 g-4 mb-4">
<div class="col">
<% field_text "email_smtp_host" "SMTP host" %>
<% field_text "email_smtp_port" "SMTP port" %>
<% field_switch "email_smtp_use_ssl" "Use TLS/SSL" %>
<% field_text "email_smtp_username" "SMTP username" %>
<% field_password "email_smtp_password" "SMTP password" %>
<% field_text "email_from_name" "Sender's name" %>
<% field_text "email_from_address" "Sender's address" "Use an email address where bounce reports can be sent to." %>
</div>
<div class="col">
<% field_text "email_to_name" "Recipient's name" %>
<% field_text "email_to_address" "Recipient's address" %>
<% field_text "email_subject" "Email subject" %>
<% field_textarea "email_body" "Email text" "Line breaks will be replaced with whitespace." %>
<% field_switch "email_attach_snapshot" "Attach snapshot" %>
<% # field_switch "email_socks5_enabled" "Use SOCKS5" "$STR_CONFIGURE_SOCKS" %>
</div>
<div class="col">
<% ex "cat $config_file" %>
</div>
</div>
<% button_submit %>
</form>

<script>
$('#email_body').style.height = "6rem";

$('#email_smtp_use_ssl').addEventListener('change', evt => {
	const elPort=$('#email_smtp_port');
	if (evt.target.checked) {
		if (elPort.value === "25") elPort.value="465";
	} else {
		if (elPort.value === "465") elPort.value="25";
	}
});
</script>

<%in _footer.cgi %>
