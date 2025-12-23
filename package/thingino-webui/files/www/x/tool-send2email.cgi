#!/bin/haserl
<%in _common.cgi %>
<%
page_title="Send to email"

domain="email"
config_file="/etc/send2.json"
temp_config_file="/tmp/$domain.json"

defaults() {
	default_for from_name "Camera $network_hostname"
	default_for trust_cert "false"
	default_for port "25"
	default_for to_name "Camera admin"
	default_for subject "Snapshot from $network_hostname"
	default_for send_photo "false"
	default_for send_video "false"
}

set_value() {
	[ -f "$temp_config_file" ] || echo '{}' > "$temp_config_file"
	jct "$temp_config_file" set "$domain.$1" "$2" >/dev/null 2>&1
}

get_value() {
	jct $config_file get "$domain.$1"
}

read_config() {
	[ -f "$config_file" ] || return

	from_address=$(get_value "from_address")
	from_name=$(get_value "from_name")
	to_address=$(get_value "to_address")
	to_name=$(get_value "to_name")
	subject=$(get_value "subject")
	body=$(get_value "body")
	host=$(get_value "host")
	port=$(get_value "port")
	username=$(get_value "username")
	password=$(get_value "password")
	use_ssl=$(get_value "use_ssl")
	trust_cert=$(get_value "trust_cert")
	send_photo=$(get_value "send_photo")
	send_video=$(get_value "send_video")
}

read_config

if [ "POST" = "$REQUEST_METHOD" ]; then
	error=""

	host="$POST_host"
	port="$POST_port"
	username="$POST_username"
	password="$POST_password"
	use_ssl="$POST_use_ssl"
	trust_cert="$POST_trust_cert"
	from_name="$POST_from_name"
	from_address="$POST_from_address"
	to_name="$POST_to_name"
	to_address="$POST_to_address"
	subject="$POST_subject"
	body="$POST_body"
	send_photo="$POST_send_photo"
	send_video="$POST_send_video"

	# normalize
	body="$(echo "$body" | tr "\r\n" " ")"

	error_if_empty "$host" "SMTP host cannot be empty."
	error_if_empty "$from_address" "Sender email address cannot be empty."
	error_if_empty "$from_name" "Sender name cannot be empty."
	error_if_empty "$to_address" "Recipient email address cannot be empty."
	error_if_empty "$to_name" "Recipient name cannot be empty."

	defaults

	if [ -z "$error" ]; then
		set_value host "$host"
		set_value port "$port"
		set_value username "$username"
		set_value password "$password"
		set_value use_ssl "$use_ssl"
		set_value trust_cert "$trust_cert"
		set_value from_name "$from_name"
		set_value from_address "$from_address"
		set_value to_name "$to_name"
		set_value to_address "$to_address"
		set_value subject "$subject"
		set_value body "$body"
		set_value send_photo "$send_photo"
		set_value send_video "$send_video"

		jct "$config_file" import "$temp_config_file"
		rm "$temp_config_file"

		redirect_to $SCRIPT_NAME "success" "Data updated."
	else
		redirect_to $SCRIPT_NAME "danger" "Error: $error"
	fi
fi

defaults
%>
<%in _header.cgi %>

<form action="<%= $SCRIPT_NAME %>" method="post" class="mb-4">
<div class="row row-cols-1 row-cols-md-2 row-cols-xl-3 g-4 mb-4">
<div class="col">
<div class="row g-1">
<div class="col-10"><% field_text "host" "SMTP server FQDN or IP address" %></div>
<div class="col-2"><% field_text "port" "Port" %></div>
</div>
<% field_text "username" "SMTP username" %>
<% field_password "password" "SMTP password" %>
<% field_switch "use_ssl" "Use TLS/SSL" %>
<% field_switch "trust_cert" "Ignore SSL certificate validity" %>
</div>
<div class="col">
<% field_text "from_name" "Sender's name" "Use a real email address where bounce reports can be sent to." %>
<% field_text "from_address" "Sender's address" %>
<% field_text "to_name" "Recipient's name" %>
<% field_text "to_address" "Recipient's address" %>
</div>
<div class="col">
<% field_text "subject" "Email subject" %>
<% field_textarea "body" "Email text" "Line breaks will be replaced with whitespaces." %>
<p class="label">Attachment</p>
<% field_switch "send_photo" "Send snapshot" %>
<% field_switch "send_video" "Send video" %>
</div>
</div>
<% button_submit %>
</form>

<button type="button" class="btn btn-dark border mb-2" title="Send to email" data-sendto="email">Test</button>

<div class="alert alert-dark ui-debug d-none">
<h4 class="mb-3">Debug info</h4>
<% ex "jct $config_file get $domain" %>
</div>

<script>
$('#body').style.height = "6rem";
$('#use_ssl').addEventListener('change', ev => {
	const el=$('#port');
	if (ev.target.checked) {
		if (el.value === "25") el.value="465";
	} else {
		if (el.value === "465") el.value="25";
	}
});
</script>

<%in _footer.cgi %>
